// Pigeon spec for the Dart↔Kotlin 7z extraction bridge.
// Regenerate: dart run pigeon --input pigeons/seven_zip_api.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/seven_zip/seven_zip_api.g.dart',
  dartOptions: DartOptions(),
  kotlinOut:
      'android/app/src/main/kotlin/com/caprado/romgi/seven_zip/SevenZipApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.caprado.romgi.seven_zip'),
  dartPackageName: 'romgi',
))

/// Live progress of a 7z extraction.
class ExtractionProgress {
  ExtractionProgress({
    required this.archivePath,
    required this.bytesExtracted,
    required this.totalBytes,
  });

  /// The archive being extracted.
  String archivePath;

  /// Bytes extracted so far.
  int bytesExtracted;

  /// Total uncompressed size in bytes. -1 if unknown.
  int totalBytes;
}

/// Methods Dart calls into Kotlin.
@HostApi()
abstract class SevenZipHostApi {
  /// Extract a 7z archive to the given output directory.
  /// Returns the path to the extracted file (or directory if multiple files).
  @async
  String extract(String archivePath, String outputDir);

  /// Cancel an in-progress extraction.
  void cancel(String archivePath);
}

/// Methods Kotlin calls into Dart. Push-style progress updates.
@FlutterApi()
abstract class SevenZipEvents {
  void onProgress(ExtractionProgress progress);
}
