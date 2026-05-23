import 'dart:async';

import '../seven_zip/seven_zip_api.g.dart';

/// Dart-side wrapper around the Pigeon-generated [SevenZipHostApi].
///
/// Provides 7z archive extraction via the native Android bridge
/// (Apache Commons Compress). Progress updates arrive through the
/// [SevenZipEvents] callback.
class SevenZipService implements SevenZipEvents {
  SevenZipService({SevenZipHostApi? api})
      : _api = api ?? SevenZipHostApi();

  final SevenZipHostApi _api;

  final _progressController =
      StreamController<ExtractionProgress>.broadcast();

  Stream<ExtractionProgress> get progressStream =>
      _progressController.stream;

  /// Extract a 7z archive to [outputDir].
  /// Returns the path to the extracted file (or directory if multiple).
  Future<String> extract(String archivePath, String outputDir) {
    SevenZipEvents.setUp(this);
    return _api.extract(archivePath, outputDir);
  }

  /// Cancel an in-progress extraction.
  Future<void> cancel(String archivePath) async {
    await _api.cancel(archivePath);
  }

  // --- SevenZipEvents (called from native) --------------------------------

  @override
  void onProgress(ExtractionProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  Future<void> dispose() async {
    await _progressController.close();
  }
}
