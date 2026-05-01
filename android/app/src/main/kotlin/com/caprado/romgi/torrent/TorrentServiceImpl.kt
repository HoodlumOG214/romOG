package com.caprado.romgi.torrent

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.frostwire.jlibtorrent.AddTorrentParams
import com.frostwire.jlibtorrent.AlertListener
import com.frostwire.jlibtorrent.Priority
import com.frostwire.jlibtorrent.SessionManager
import com.frostwire.jlibtorrent.SessionParams
import com.frostwire.jlibtorrent.SettingsPack
import com.frostwire.jlibtorrent.Sha1Hash
import com.frostwire.jlibtorrent.TorrentHandle
import com.frostwire.jlibtorrent.TorrentInfo
import com.frostwire.jlibtorrent.TorrentStatus
import com.frostwire.jlibtorrent.alerts.Alert
import com.frostwire.jlibtorrent.alerts.AlertType
import com.frostwire.jlibtorrent.alerts.TorrentErrorAlert
import com.frostwire.jlibtorrent.alerts.TorrentFinishedAlert
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Wraps a [SessionManager] and surfaces it through [TorrentHostApi].
 * One session per app process. [start] is idempotent.
 */
class TorrentServiceImpl(
    @Suppress("unused") private val context: Context,
    binaryMessenger: BinaryMessenger,
) : TorrentHostApi {

    private val events = TorrentEvents(binaryMessenger)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val knownInfohashes: MutableSet<String> =
        Collections.newSetFromMap(ConcurrentHashMap())

    private val pollingExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "torrent-poll").apply { isDaemon = true }
        }
    private var pollFuture: ScheduledFuture<*>? = null

    @Volatile private var session: SessionManager? = null
    @Volatile private var currentSettings: TorrentSettings? = null

    // --- Lifecycle --------------------------------------------------------

    @Synchronized
    override fun start(settings: TorrentSettings) {
        val existing = session
        if (existing != null) {
            updateSettings(settings)
            return
        }
        currentSettings = settings
        File(settings.savePath).mkdirs()

        val sm = SessionManager().also {
            it.start(SessionParams(buildSettingsPack(settings)))
            it.addListener(alertListener)
        }
        session = sm

        pollFuture = pollingExecutor.scheduleAtFixedRate(
            ::emitProgressSnapshot, 1, 1, TimeUnit.SECONDS
        )
    }

    @Synchronized
    override fun updateSettings(settings: TorrentSettings) {
        currentSettings = settings
        val sm = session ?: return
        sm.applySettings(buildSettingsPack(settings))
    }

    // --- Add / cancel ----------------------------------------------------

    @Synchronized
    override fun addTorrent(request: AddTorrentRequest): String {
        val sm = requireSession()
        val saveDir = File(requireNotNull(currentSettings).savePath).apply { mkdirs() }

        val infohash: String
        val handle: TorrentHandle?

        val magnet = request.magnet
        val bytes = request.torrentBytes

        when {
            magnet != null && magnet.isNotBlank() -> {
                val parsed = AddTorrentParams.parseMagnetUri(magnet)
                infohash = parsed.infoHashes().v1.toHex().lowercase()
                if (sm.find(Sha1Hash(infohash)) == null) {
                    sm.download(magnet, saveDir)
                }
                handle = sm.find(Sha1Hash(infohash))
            }
            bytes != null && bytes.isNotEmpty() -> {
                val info = TorrentInfo.bdecode(bytes)
                infohash = info.infoHash().toHex().lowercase()
                if (sm.find(Sha1Hash(infohash)) == null) {
                    sm.download(info, saveDir)
                }
                handle = sm.find(Sha1Hash(infohash))
            }
            else -> throw IllegalArgumentException(
                "AddTorrentRequest needs either a magnet or torrentBytes"
            )
        }

        knownInfohashes += infohash
        handle?.let { applyFilePriorities(it, request.fileIndices) }
        return infohash
    }

    @Synchronized
    override fun cancel(infohash: String) {
        val sm = session ?: return
        val handle = sm.find(Sha1Hash(infohash)) ?: return
        // Partial files stay on disk so the user can resume by re-adding.
        sm.remove(handle)
        knownInfohashes -= infohash
    }

    @Synchronized
    override fun pauseAll() {
        session?.pause()
    }

    @Synchronized
    override fun resumeAll() {
        session?.resume()
    }

    override fun listAll(): List<TorrentProgress> {
        val sm = session ?: return emptyList()
        return knownInfohashes.mapNotNull { ih ->
            sm.find(Sha1Hash(ih))?.let(::buildProgress)
        }
    }

    // --- Internals -------------------------------------------------------

    private val alertListener = object : AlertListener {
        override fun types(): IntArray = intArrayOf(
            AlertType.TORRENT_FINISHED.swig(),
            AlertType.TORRENT_ERROR.swig(),
        )

        override fun alert(alert: Alert<*>) {
            when (alert.type()) {
                AlertType.TORRENT_FINISHED -> {
                    val a = alert as TorrentFinishedAlert
                    if (currentSettings?.seedingEnabled == false) {
                        a.handle().pause()
                    }
                }
                AlertType.TORRENT_ERROR -> {
                    val a = alert as TorrentErrorAlert
                    val ih = a.handle().infoHash().toHex().lowercase()
                    val msg = a.error()?.message() ?: "torrent error"
                    mainHandler.post {
                        events.onError(ih, msg) { /* fire-and-forget */ }
                    }
                }
                else -> {}
            }
        }
    }

    private fun emitProgressSnapshot() {
        val sm = session ?: return
        for (ih in knownInfohashes.toList()) {
            val handle = sm.find(Sha1Hash(ih)) ?: continue
            val progress = buildProgress(handle)
            mainHandler.post {
                events.onProgress(progress) { /* fire-and-forget */ }
            }
        }
    }

    private fun buildProgress(handle: TorrentHandle): TorrentProgress {
        val status = handle.status()
        val info = handle.torrentFile()
        val files = if (info != null) {
            (0 until info.numFiles()).map { i ->
                val priority = handle.filePriority(i)
                TorrentFile(
                    index = i.toLong(),
                    path = info.files().filePath(i),
                    length = info.files().fileSize(i),
                    bytesDownloaded = handle.fileProgress()?.getOrNull(i) ?: 0L,
                    priority = priorityToInt(priority).toLong(),
                )
            }
        } else emptyList()

        return TorrentProgress(
            infohash = handle.infoHash().toHex().lowercase(),
            name = status.name() ?: "",
            state = stateToString(status.state()),
            totalSize = info?.totalSize() ?: status.totalDone(),
            bytesDownloaded = status.totalDone(),
            downloadRate = status.downloadRate().toLong(),
            uploadRate = status.uploadRate().toLong(),
            peers = status.numPeers().toLong(),
            seeds = status.numSeeds().toLong(),
            error = status.errc()?.message() ?: "",
            files = files,
        )
    }

    private fun applyFilePriorities(handle: TorrentHandle, requestedIndices: List<Long>) {
        val info = handle.torrentFile() ?: return
        val n = info.numFiles()
        if (requestedIndices.isEmpty()) {
            for (i in 0 until n) handle.filePriority(i, Priority.NORMAL)
            return
        }
        val wanted = requestedIndices.map { it.toInt() }.toSet()
        for (i in 0 until n) {
            val current = handle.filePriority(i)
            val next = when {
                i in wanted -> Priority.NORMAL
                current == Priority.IGNORE -> Priority.IGNORE
                else -> current
            }
            handle.filePriority(i, next)
        }
    }

    private fun requireSession(): SessionManager =
        session ?: error("TorrentService not started. Call start() first.")

    private fun buildSettingsPack(s: TorrentSettings): SettingsPack {
        val pack = SettingsPack()
            .connectionsLimit(s.maxConnections.toInt())
            .uploadRateLimit(s.maxUploadRateBytesPerSec.toInt())
            .downloadRateLimit(s.maxDownloadRateBytesPerSec.toInt())
        pack.setInteger(
            com.frostwire.jlibtorrent.swig.settings_pack.int_types.unchoke_slots_limit.swigValue(),
            s.maxUploads.toInt(),
        )
        pack.setBoolean(
            com.frostwire.jlibtorrent.swig.settings_pack.bool_types.enable_dht.swigValue(),
            s.dhtEnabled,
        )
        return pack
    }

    private fun stateToString(state: TorrentStatus.State?): String = when (state) {
        TorrentStatus.State.QUEUED_FOR_CHECKING -> "queued"
        TorrentStatus.State.CHECKING_FILES -> "checking_files"
        TorrentStatus.State.DOWNLOADING_METADATA -> "downloading_metadata"
        TorrentStatus.State.DOWNLOADING -> "downloading"
        TorrentStatus.State.FINISHED -> "finished"
        TorrentStatus.State.SEEDING -> "seeding"
        TorrentStatus.State.ALLOCATING -> "allocating"
        TorrentStatus.State.CHECKING_RESUME_DATA -> "checking_resume"
        else -> "unknown"
    }

    private fun priorityToInt(p: Priority): Int = when (p) {
        Priority.IGNORE -> 0
        Priority.LOW -> 1
        Priority.NORMAL -> 4
        Priority.HIGH -> 6
        Priority.TOP_PRIORITY -> 7
        else -> 4
    }

    fun shutdown() {
        pollFuture?.cancel(false)
        pollingExecutor.shutdownNow()
        session?.stop()
        session = null
    }
}
