// IAAuthManager tests.
//
// Covers: HTML parser, JSON round-trip, persistence across simulated
// process restart, legacy-storage cleanup, validation status transitions,
// 401 failure counting + circuit-breaker, completeLoginFromCookies
// happy + sad paths.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/internet_archive_auth_manager.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store;

  _InMemorySecureStorage(this._store) : super();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

/// Dio adapter that returns canned responses keyed by request URL.
class _StubAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> _routes;
  final List<RequestOptions> calls = [];

  _StubAdapter(this._routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    final handler = _routes[url] ?? _routes[options.path] ?? _routes['*'];
    if (handler == null) {
      return ResponseBody.fromString('not stubbed', 500);
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(String body) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );

ResponseBody _status(int code) => ResponseBody.fromString('', code);


void main() {
  group('IASession', () {
    test('round-trips through JSON', () {
      final created = DateTime.utc(2026, 4, 30, 10, 0, 0);
      final session = IASession(
        username: 'tester',
        accessKey: 'A' * 16,
        secretKey: 'B' * 16,
        createdAt: created,
        lastValidatedAt: created,
        lastValidationStatus: IAValidationStatus.ok,
        failureCount: 1,
      );
      final json = jsonEncode(session.toJson());
      final back = IASession.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(back.username, 'tester');
      expect(back.accessKey, session.accessKey);
      expect(back.secretKey, session.secretKey);
      expect(back.lastValidationStatus, IAValidationStatus.ok);
      expect(back.failureCount, 1);
      expect(back.createdAt.toUtc(), created);
    });

    test('falls back gracefully on missing/invalid fields', () {
      final s = IASession.fromJson({});
      expect(s.username, '');
      expect(s.accessKey, '');
      expect(s.lastValidationStatus, IAValidationStatus.unverified);
      expect(s.failureCount, 0);
    });
  });

  group('isLoggedIn / persistence across restart', () {
    test('returns false when no session is stored', () async {
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage({}),
        dio: Dio()..httpClientAdapter = _StubAdapter({}),
      );
      expect(await auth.isLoggedIn(), isFalse);
    });

    test('persists across simulated process restart', () async {
      final store = <String, String>{};
      final stubDio = Dio()
        ..httpClientAdapter = _StubAdapter({
          'https://archive.org/account/s3.php': (req) => _ok(
                '<html><input name="access" value="ABCD1234XYZ" />'
                '<input name="secret" value="SECRETKEY9999" /></html>',
              ),
        });

      final auth1 = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: stubDio,
      );
      final session = await auth1.completeLoginFromCookies({
        'logged-in-user': 'tester',
        'logged-in-sig': 'sig',
      });
      expect(session, isNotNull);
      expect(await auth1.isLoggedIn(), isTrue);
      // Issue #5: re-instantiate against the *same* underlying store —
      // the new manager must surface the same logged-in state.
      final auth2 = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: Dio()..httpClientAdapter = _StubAdapter({}),
      );
      expect(await auth2.isLoggedIn(), isTrue);
      expect(await auth2.getUsername(), 'tester');
    });
  });

  group('completeLoginFromCookies', () {
    test('returns null and writes nothing if s3.php has no keys', () async {
      final store = <String, String>{};
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: Dio()
          ..httpClientAdapter = _StubAdapter({
            'https://archive.org/account/s3.php':
                (req) => _ok('<html>nothing here</html>'),
          }),
      );
      final session = await auth.completeLoginFromCookies({
        'logged-in-user': 'tester',
      });
      expect(session, isNull);
      expect(await auth.isLoggedIn(), isFalse);
      expect(store, isEmpty);
    });

    test('parses access/secret keys from s3.php HTML', () async {
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage({}),
        dio: Dio()
          ..httpClientAdapter = _StubAdapter({
            'https://archive.org/account/s3.php': (req) => _ok(
                  '<html><body>'
                  '<input type="text" name="access" value="K1" readonly>'
                  '<input type="text" name="secret" value="K2" readonly>'
                  '</body></html>',
                ),
          }),
      );
      final session = await auth.completeLoginFromCookies({
        'logged-in-user': 'tester',
        'logged-in-sig': 'sig',
      });
      expect(session, isNotNull);
      expect(session!.accessKey, 'K1');
      expect(session.secretKey, 'K2');
      expect(session.lastValidationStatus, IAValidationStatus.ok);
    });
  });

  group('validate / failure handling', () {
    Future<IAAuthManager> seeded(int status, {int failures = 0}) async {
      final store = <String, String>{};
      final adapter = _StubAdapter({
        'https://archive.org/account/s3.php': (req) => _ok(
              '<input name="access" value="A" />'
              '<input name="secret" value="B" />',
            ),
        'https://s3.us.archive.org/?check_auth=1': (req) => _status(status),
      });
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: Dio()..httpClientAdapter = adapter,
      );
      await auth.completeLoginFromCookies({
        'logged-in-user': 'tester',
        'logged-in-sig': 'sig',
      });
      // Manually bump failures to test the threshold.
      for (var i = 0; i < failures; i++) {
        await auth.recordAuthFailure();
      }
      return auth;
    }

    test('200 → ok status', () async {
      final auth = await seeded(200);
      expect(await auth.validate(), IAValidationStatus.ok);
    });

    test('401 → invalid status', () async {
      final auth = await seeded(401);
      expect(await auth.validate(), IAValidationStatus.invalid);
    });

    test('500 → stale, not invalid', () async {
      final auth = await seeded(500);
      expect(await auth.validate(), IAValidationStatus.stale);
    });

    test('three recordAuthFailure calls trip the circuit-breaker', () async {
      final auth = await seeded(200, failures: 3);
      expect(await auth.isLoggedIn(), isFalse);
      final session = await auth.currentSession();
      expect(session?.lastValidationStatus, IAValidationStatus.invalid);
    });
  });

  group('migrateFromV1IfNeeded', () {
    test('removes legacy cookie keys without disturbing the current blob', () async {
      final store = <String, String>{
        'ia_cookie_logged-in-user': 'old',
        'ia_cookie_logged-in-sig': 'old',
        'ia_cookie_PHPSESSID': 'old',
        'ia_logged_in': 'true',
        'ia_username': 'old-tester',
        'ia.session.v2': jsonEncode({
          'schemaVersion': 2,
          'username': 'tester',
          'accessKey': 'A',
          'secretKey': 'B',
          'createdAt': DateTime.now().toIso8601String(),
          'lastValidatedAt': DateTime.now().toIso8601String(),
          'lastValidationStatus': 'ok',
          'failureCount': 0,
        }),
      };
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: Dio()..httpClientAdapter = _StubAdapter({}),
      );
      await auth.migrateFromV1IfNeeded();
      expect(store.containsKey('ia_cookie_logged-in-user'), isFalse);
      expect(store.containsKey('ia_cookie_logged-in-sig'), isFalse);
      expect(store.containsKey('ia_cookie_PHPSESSID'), isFalse);
      expect(store.containsKey('ia_logged_in'), isFalse);
      expect(store.containsKey('ia_username'), isFalse);
      expect(store.containsKey('ia.session.v2'), isTrue);
      // v2 session survives.
      expect(await auth.isLoggedIn(), isTrue);
      expect(await auth.getUsername(), 'tester');
    });

    test('is idempotent', () async {
      final store = <String, String>{
        'ia_cookie_logged-in-user': 'old',
      };
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage(store),
        dio: Dio()..httpClientAdapter = _StubAdapter({}),
      );
      await auth.migrateFromV1IfNeeded();
      await auth.migrateFromV1IfNeeded();
      expect(store.containsKey('ia_cookie_logged-in-user'), isFalse);
    });
  });

  group('applyHeaders', () {
    test('injects Authorization header when session exists', () async {
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage({}),
        dio: Dio()
          ..httpClientAdapter = _StubAdapter({
            'https://archive.org/account/s3.php': (req) => _ok(
                  '<input name="access" value="ACCESS" />'
                  '<input name="secret" value="SECRET" />',
                ),
          }),
      );
      await auth.completeLoginFromCookies({
        'logged-in-user': 'tester',
      });
      final headers = <String, dynamic>{};
      await auth.applyHeaders(headers);
      expect(headers['Authorization'], 'LOW ACCESS:SECRET');
    });

    test('no-op when no session', () async {
      final auth = IAAuthManager(
        storage: _InMemorySecureStorage({}),
        dio: Dio()..httpClientAdapter = _StubAdapter({}),
      );
      final headers = <String, dynamic>{};
      await auth.applyHeaders(headers);
      expect(headers, isEmpty);
    });
  });

  group('isInternetArchiveUrl', () {
    test('matches archive.org hosts', () {
      expect(IAAuthManager.isInternetArchiveUrl('https://archive.org/x'), isTrue);
      expect(IAAuthManager.isInternetArchiveUrl('https://s3.us.archive.org/'), isTrue);
    });
    test('rejects unrelated hosts', () {
      expect(IAAuthManager.isInternetArchiveUrl('https://example.com/'), isFalse);
    });
  });
}
