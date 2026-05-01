import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/download_link.dart';
import 'package:romgi/services/host_adapter.dart';
import 'package:romgi/services/internet_archive_auth_manager.dart';

class _StubAuth extends IAAuthManager {
  _StubAuth({this.loggedIn = true})
      : super(
          storage: _NoOpStorage(),
          dio: Dio()..httpClientAdapter = _NoOpAdapter(),
        );

  bool loggedIn;
  bool ensureFreshCalled = false;
  bool applyHeadersCalled = false;
  int authFailures = 0;

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> ensureFresh() async {
    ensureFreshCalled = true;
  }

  @override
  Future<void> applyHeaders(Map<String, dynamic> headers) async {
    applyHeadersCalled = true;
    headers['Authorization'] = 'LOW K1:K2';
  }

  @override
  Future<void> recordAuthFailure() async {
    authFailures++;
  }
}

class _NoOpStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;
}

class _NoOpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', 500);

  @override
  void close({bool force = false}) {}
}

DownloadLink _http({String? sourceId, bool requiresAuth = false}) {
  return DownloadLink(
    name: 'rom',
    type: 'Game',
    format: 'zip',
    url: 'https://example.com/file.zip',
    filename: 'file.zip',
    host: 'Example',
    size: 1,
    sizeStr: '1',
    sourceUrl: 'https://example.com/',
    sourceId: sourceId,
    requiresAuth: requiresAuth,
  );
}

DownloadLink _ia({bool requiresAuth = false}) {
  return DownloadLink(
    name: 'rom',
    type: 'Game',
    format: 'zip',
    url: 'https://archive.org/file.zip',
    filename: 'file.zip',
    host: 'Internet Archive',
    size: 1,
    sizeStr: '1',
    sourceUrl: 'https://archive.org/',
    sourceId: 'internet_archive',
    requiresAuth: requiresAuth,
  );
}

DownloadLink _torrent() {
  return DownloadLink(
    name: 'rom',
    type: 'Game',
    format: 'zip',
    url: 'https://x/y.torrent',
    filename: 'file.zip',
    host: 'MiNERVA Archive',
    size: 1,
    sizeStr: '1',
    sourceUrl: 'https://x/',
    sourceId: 'minerva',
    torrentInfohash: 'aabbccddeeff00112233445566778899aabbccdd',
    torrentFileIndex: 0,
    torrentFilePath: 'file.zip',
  );
}

void main() {
  group('HostAdapterRegistry', () {
    test('routes torrent links to the torrent adapter', () {
      final reg = HostAdapterRegistry();
      expect(reg.adapterFor(_torrent()).isTorrent, isTrue);
    });

    test('routes IA links via sourceId to InternetArchiveAdapter', () {
      final auth = _StubAuth();
      final reg = HostAdapterRegistry(internetArchive: InternetArchiveAdapter(auth));
      final adapter = reg.adapterFor(_ia());
      expect(adapter, isA<InternetArchiveAdapter>());
    });

    test('routes archive.org URLs to InternetArchiveAdapter even without sourceId', () {
      final auth = _StubAuth();
      final reg = HostAdapterRegistry(internetArchive: InternetArchiveAdapter(auth));
      final link = DownloadLink(
        name: 'rom',
        type: 'Game',
        format: 'zip',
        url: 'https://archive.org/legacy/file.zip',
        filename: 'file.zip',
        host: 'Archive',
        size: 1,
        sizeStr: '1',
        sourceUrl: '',
      );
      expect(reg.adapterFor(link), isA<InternetArchiveAdapter>());
    });

    test('routes everything else to the default HTTP adapter', () {
      final reg = HostAdapterRegistry();
      expect(reg.adapterFor(_http(sourceId: 'mariocube')),
          isA<DefaultHttpAdapter>());
    });

    test('falls back to default HTTP if no IA adapter is provided', () {
      final reg = HostAdapterRegistry();
      expect(reg.adapterFor(_ia()), isA<DefaultHttpAdapter>());
    });
  });

  group('InternetArchiveAdapter', () {
    test('canStartDownload returns true for non-auth links', () async {
      final adapter = InternetArchiveAdapter(_StubAuth(loggedIn: false));
      expect(await adapter.canStartDownload(_ia()), isTrue);
    });

    test('canStartDownload requires login for auth-required links', () async {
      final loggedOut = InternetArchiveAdapter(_StubAuth(loggedIn: false));
      final loggedIn = InternetArchiveAdapter(_StubAuth(loggedIn: true));
      expect(await loggedOut.canStartDownload(_ia(requiresAuth: true)), isFalse);
      expect(await loggedIn.canStartDownload(_ia(requiresAuth: true)), isTrue);
    });

    test('prepareHeaders runs ensureFresh + applyHeaders', () async {
      final auth = _StubAuth();
      final adapter = InternetArchiveAdapter(auth);
      final headers = <String, dynamic>{};
      await adapter.prepareHeaders(headers, _ia());
      expect(auth.ensureFreshCalled, isTrue);
      expect(auth.applyHeadersCalled, isTrue);
      expect(headers['Authorization'], 'LOW K1:K2');
    });

    test('onAuthFailure increments the auth failure counter', () async {
      final auth = _StubAuth();
      final adapter = InternetArchiveAdapter(auth);
      await adapter.onAuthFailure(_ia());
      await adapter.onAuthFailure(_ia());
      expect(auth.authFailures, 2);
    });
  });

  group('DefaultHttpAdapter', () {
    test('does nothing in prepareHeaders', () async {
      final adapter = DefaultHttpAdapter();
      final headers = <String, dynamic>{'X': '1'};
      await adapter.prepareHeaders(headers, _http());
      expect(headers, {'X': '1'});
    });

    test('canStartDownload always true', () async {
      final adapter = DefaultHttpAdapter();
      expect(await adapter.canStartDownload(_http(requiresAuth: true)), isTrue);
    });
  });
}
