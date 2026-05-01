package com.caprado.romgi

import com.caprado.romgi.torrent.TorrentHostApi
import com.caprado.romgi.torrent.TorrentServiceImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var torrentService: TorrentServiceImpl? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val service = TorrentServiceImpl(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        torrentService = service
        TorrentHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, service)
    }

    override fun onDestroy() {
        torrentService?.shutdown()
        torrentService = null
        super.onDestroy()
    }
}
