import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../torrent/torrent_api.g.dart';

/// Dart-side wrapper around the Pigeon-generated [TorrentHostApi].
///
/// Owns the broadcast streams the UI watches (per-infohash and global)
/// and a cache of the latest [TorrentProgress] snapshot keyed by
/// infohash. Native progress updates arrive through the [TorrentEvents]
/// callback, which this class implements.
class TorrentService implements TorrentEvents {
  TorrentService({TorrentHostApi? api, Future<String> Function()? savePathResolver})
      : _api = api ?? TorrentHostApi(),
        _savePathResolver = savePathResolver ?? _defaultSavePath;

  final TorrentHostApi _api;
  final Future<String> Function() _savePathResolver;

  static Future<String> _defaultSavePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'torrents');
  }
  final _progressController =
      StreamController<TorrentProgress>.broadcast();
  final _errorController =
      StreamController<({String infohash, String error})>.broadcast();
  final Map<String, TorrentProgress> _latest = {};

  bool _started = false;

  Stream<TorrentProgress> get progressStream => _progressController.stream;

  Stream<({String infohash, String error})> get errorStream =>
      _errorController.stream;

  /// Last-known snapshot per infohash. Empty when nothing's running.
  Map<String, TorrentProgress> get latest => Map.unmodifiable(_latest);

  /// One-shot fetch of every active torrent's snapshot from the runtime.
  Future<List<TorrentProgress>> snapshot() async {
    if (!_started) return const [];
    return _api.listAll();
  }

  /// Start the native session. Idempotent; safe to call from app bootstrap
  /// and again whenever settings change.
  Future<void> start({required bool seedingEnabled}) async {
    if (_started) {
      await updateSeeding(seedingEnabled);
      return;
    }
    final settings = await _buildSettings(seedingEnabled: seedingEnabled);
    TorrentEvents.setUp(this);
    await _api.start(settings);
    _started = true;
  }

  Future<void> updateSeeding(bool seedingEnabled) async {
    if (!_started) return;
    final settings = await _buildSettings(seedingEnabled: seedingEnabled);
    await _api.updateSettings(settings);
  }

  Future<String> addTorrent({
    String? magnet,
    List<int>? torrentBytes,
    List<int> fileIndices = const [],
  }) async {
    if (!_started) {
      throw StateError('TorrentService.start() must be called before addTorrent');
    }
    if ((magnet == null || magnet.isEmpty) &&
        (torrentBytes == null || torrentBytes.isEmpty)) {
      throw ArgumentError('Either magnet or torrentBytes is required');
    }
    final request = AddTorrentRequest(
      magnet: magnet,
      torrentBytes: torrentBytes == null ? null : Uint8List.fromList(torrentBytes),
      fileIndices: fileIndices,
    );
    return _api.addTorrent(request);
  }

  Future<void> cancel(String infohash) async {
    if (!_started) return;
    _latest.remove(infohash);
    await _api.cancel(infohash);
  }

  Future<void> pauseAll() async {
    if (!_started) return;
    await _api.pauseAll();
  }

  Future<void> resumeAll() async {
    if (!_started) return;
    await _api.resumeAll();
  }

  // --- TorrentEvents (called from native) -------------------------------

  @override
  void onProgress(TorrentProgress progress) {
    _latest[progress.infohash] = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  @override
  void onError(String infohash, String error) {
    if (!_errorController.isClosed) {
      _errorController.add((infohash: infohash, error: error));
    }
  }

  // --- Internals --------------------------------------------------------

  Future<TorrentSettings> _buildSettings({required bool seedingEnabled}) async {
    final savePath = await _savePathResolver();
    return TorrentSettings(
      savePath: savePath,
      seedingEnabled: seedingEnabled,
      dhtEnabled: true,
      maxConnections: 200,
      maxUploads: 4,
      maxDownloadRateBytesPerSec: 0,
      maxUploadRateBytesPerSec: 0,
    );
  }

  Future<void> dispose() async {
    await _progressController.close();
    await _errorController.close();
  }
}
