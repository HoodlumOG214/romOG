import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of a session validation probe.
enum IAValidationStatus { unverified, ok, stale, invalid }

/// Persisted IA session blob.
class IASession {
  final int schemaVersion;
  final String username;
  final String accessKey;
  final String secretKey;
  final DateTime createdAt;
  final DateTime lastValidatedAt;
  final IAValidationStatus lastValidationStatus;
  final int failureCount;

  const IASession({
    this.schemaVersion = 2,
    required this.username,
    required this.accessKey,
    required this.secretKey,
    required this.createdAt,
    required this.lastValidatedAt,
    this.lastValidationStatus = IAValidationStatus.unverified,
    this.failureCount = 0,
  });

  IASession copyWith({
    String? username,
    String? accessKey,
    String? secretKey,
    DateTime? createdAt,
    DateTime? lastValidatedAt,
    IAValidationStatus? lastValidationStatus,
    int? failureCount,
  }) {
    return IASession(
      schemaVersion: schemaVersion,
      username: username ?? this.username,
      accessKey: accessKey ?? this.accessKey,
      secretKey: secretKey ?? this.secretKey,
      createdAt: createdAt ?? this.createdAt,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      lastValidationStatus: lastValidationStatus ?? this.lastValidationStatus,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'username': username,
        'accessKey': accessKey,
        'secretKey': secretKey,
        'createdAt': createdAt.toIso8601String(),
        'lastValidatedAt': lastValidatedAt.toIso8601String(),
        'lastValidationStatus': lastValidationStatus.name,
        'failureCount': failureCount,
      };

  factory IASession.fromJson(Map<String, dynamic> json) {
    return IASession(
      schemaVersion: json['schemaVersion'] as int? ?? 2,
      username: json['username'] as String? ?? '',
      accessKey: json['accessKey'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']),
      lastValidatedAt: _parseDate(json['lastValidatedAt']),
      lastValidationStatus: _parseStatus(json['lastValidationStatus']),
      failureCount: json['failureCount'] as int? ?? 0,
    );
  }

  static DateTime _parseDate(Object? raw) {
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  static IAValidationStatus _parseStatus(Object? raw) {
    if (raw is String) {
      for (final s in IAValidationStatus.values) {
        if (s.name == raw) return s;
      }
    }
    return IAValidationStatus.unverified;
  }
}

/// Internet Archive session lifecycle.
///
/// One JSON blob in [FlutterSecureStorage] under [_storageKey] so reads
/// and writes are atomic. Auth uses S3-style tokens fetched from
/// `/account/s3.php` after WebView login; cookies are discarded after
/// the keys are stored. Tokens have no documented TTL — we re-validate
/// by probing `s3.us.archive.org`.
class IAAuthManager {
  static const String _storageKey = 'ia.session.v2';

  /// Legacy storage keys (cookie-only auth) — wiped on first launch.
  static const List<String> _v1CookieNames = [
    'logged-in-user',
    'logged-in-sig',
    'ia-auth',
    'PHPSESSID',
  ];
  static const String _v1CookieKeyPrefix = 'ia_cookie_';
  static const String _v1LoggedInKey = 'ia_logged_in';
  static const String _v1UsernameKey = 'ia_username';

  static const Duration _staleAfter = Duration(hours: 24);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const int _maxFailures = 3;

  static const String _s3KeysUrl = 'https://archive.org/account/s3.php';
  static const String _s3ProbeUrl =
      'https://s3.us.archive.org/?check_auth=1';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  final Completer<void> _writeLock = Completer<void>()..complete();
  bool _v1Migrated = false;
  IASession? _cached;

  IAAuthManager({FlutterSecureStorage? storage, Dio? dio})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  // ---- Public surface --------------------------------------------------

  /// A usable session exists (not circuit-broken). Does not probe.
  Future<bool> isLoggedIn() async {
    final s = await _readSession();
    if (s == null) return false;
    return s.failureCount < _maxFailures &&
        s.lastValidationStatus != IAValidationStatus.invalid;
  }

  Future<String?> getUsername() async {
    final s = await _readSession();
    return s?.username;
  }

  Future<IASession?> currentSession() => _readSession();

  /// Inject the IA Authorization header on a Dio request. No-op when no
  /// session is present — gate upstream via [isLoggedIn] when the link
  /// requires auth.
  Future<void> sign(RequestOptions options) async {
    final s = await _readSession();
    if (s == null) return;
    options.headers['Authorization'] =
        'LOW ${s.accessKey}:${s.secretKey}';
  }

  /// Inject the IA Authorization header into a headers map. Used by
  /// the download path that builds the headers map directly.
  Future<void> applyHeaders(Map<String, dynamic> headers) async {
    final s = await _readSession();
    if (s == null) return;
    headers['Authorization'] = 'LOW ${s.accessKey}:${s.secretKey}';
  }

  /// Complete login after the WebView captures cookies. GETs
  /// `/account/s3.php` with those cookies, parses the access/secret
  /// keys, persists them, and discards the cookies.
  Future<IASession?> completeLoginFromCookies(
    Map<String, String> cookies,
  ) async {
    final cookieHeader = cookies.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    final username = cookies['logged-in-user'] ?? '';

    try {
      final response = await _dio.get<String>(
        _s3KeysUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Cookie': cookieHeader,
            'User-Agent': 'romgi/1.x (IAAuthManager)',
          },
          followRedirects: true,
        ),
      );
      final body = response.data ?? '';
      final keys = _parseS3KeysFromHtml(body);
      if (keys == null) return null;

      final now = DateTime.now();
      final session = IASession(
        username: username,
        accessKey: keys.access,
        secretKey: keys.secret,
        createdAt: now,
        lastValidatedAt: now,
        lastValidationStatus: IAValidationStatus.ok,
      );
      await _writeSession(session);
      return session;
    } catch (_) {
      return null;
    }
  }

  /// Probe `s3.us.archive.org/?check_auth=1` and update the persisted
  /// validation status.
  Future<IAValidationStatus> validate() async {
    final s = await _readSession();
    if (s == null) return IAValidationStatus.invalid;
    try {
      final response = await _dio.head(
        _s3ProbeUrl,
        options: Options(
          headers: {
            'Authorization': 'LOW ${s.accessKey}:${s.secretKey}',
          },
          sendTimeout: _probeTimeout,
          receiveTimeout: _probeTimeout,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      final ok = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      final status = ok
          ? IAValidationStatus.ok
          : (response.statusCode == 401 || response.statusCode == 403
              ? IAValidationStatus.invalid
              : IAValidationStatus.stale);
      await _writeSession(s.copyWith(
        lastValidatedAt: DateTime.now(),
        lastValidationStatus: status,
        failureCount: ok ? 0 : s.failureCount,
      ));
      return status;
    } catch (_) {
      // Network/transport failure — mark stale, not invalid.
      await _writeSession(s.copyWith(
        lastValidatedAt: DateTime.now(),
        lastValidationStatus: IAValidationStatus.stale,
      ));
      return IAValidationStatus.stale;
    }
  }

  /// Probe only if the cached session is older than [_staleAfter].
  Future<void> ensureFresh() async {
    final s = await _readSession();
    if (s == null) return;
    if (DateTime.now().difference(s.lastValidatedAt) >= _staleAfter) {
      await validate();
    }
  }

  /// Bump failure count after a 401/403. Once over [_maxFailures] the
  /// session is marked invalid and `isLoggedIn()` returns false.
  Future<void> recordAuthFailure() async {
    final s = await _readSession();
    if (s == null) return;
    final next = s.copyWith(
      failureCount: s.failureCount + 1,
      lastValidationStatus: s.failureCount + 1 >= _maxFailures
          ? IAValidationStatus.invalid
          : s.lastValidationStatus,
    );
    await _writeSession(next);
  }

  Future<void> logout() async {
    await _writeSession(null);
  }

  /// Wipe legacy cookie-only storage. Idempotent.
  Future<void> migrateFromV1IfNeeded() async {
    if (_v1Migrated) return;
    _v1Migrated = true;
    for (final c in _v1CookieNames) {
      try {
        await _storage.delete(key: '$_v1CookieKeyPrefix$c');
      } catch (_) {}
    }
    try {
      await _storage.delete(key: _v1LoggedInKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _v1UsernameKey);
    } catch (_) {}
  }

  static bool isInternetArchiveUrl(String url) => url.contains('archive.org');

  // ---- Internals -------------------------------------------------------

  Future<IASession?> _readSession() async {
    if (_cached != null) return _cached;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final s = IASession.fromJson(json);
      _cached = s;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSession(IASession? session) async {
    // secure_storage isn't transactional; serialize writes ourselves.
    while (!_writeLock.isCompleted) {
      await _writeLock.future;
    }
    final ours = Completer<void>();
    try {
      _cached = session;
      if (session == null) {
        await _storage.delete(key: _storageKey);
      } else {
        final blob = jsonEncode(session.toJson());
        await _storage.write(key: _storageKey, value: blob);
      }
    } finally {
      ours.complete();
    }
  }

  /// Pull access/secret keys out of `/account/s3.php`. The page embeds
  /// them in `<input>` fields named "access" and "secret"; if IA's HTML
  /// drifts this returns null and the login flow shows a retry banner.
  static _Keys? _parseS3KeysFromHtml(String html) {
    final access = _matchInputValue(html, 'access');
    final secret = _matchInputValue(html, 'secret');
    if (access != null && secret != null) {
      return _Keys(access: access, secret: secret);
    }
    return null;
  }

  static String? _matchInputValue(String html, String name) {
    // <input ... name="access" value="XXXX" ...>  or vice versa.
    // Quotes can be single or double; attribute order is unstable.
    final patterns = <RegExp>[
      RegExp(
        '<input[^>]*\\bname=["\']$name["\'][^>]*\\bvalue=["\']([^"\']+)',
        caseSensitive: false,
      ),
      RegExp(
        '<input[^>]*\\bvalue=["\']([^"\']+)["\'][^>]*\\bname=["\']$name',
        caseSensitive: false,
      ),
    ];
    for (final r in patterns) {
      final m = r.firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }
}

class _Keys {
  final String access;
  final String secret;
  const _Keys({required this.access, required this.secret});
}
