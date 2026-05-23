import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/providers.dart';

class InternetArchiveLoginScreen extends ConsumerStatefulWidget {
  const InternetArchiveLoginScreen({super.key});

  @override
  ConsumerState<InternetArchiveLoginScreen> createState() =>
      _InternetArchiveLoginScreenState();
}

class _InternetArchiveLoginScreenState
    extends ConsumerState<InternetArchiveLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';

  static const String _loginUrl = 'https://archive.org/account/login';
  static const String _accountUrl = 'https://archive.org/account/';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });

            if (url.startsWith(_accountUrl) || url == 'https://archive.org/') {
              await _extractAndSaveCookies();
            }
          },
          onWebResourceError: (_) {},
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  bool _exchangeInProgress = false;

  Future<void> _extractAndSaveCookies() async {
    if (_exchangeInProgress) return;
    _exchangeInProgress = true;
    try {
      // Fetch s3.php from within the WebView via XHR so that all cookies
      // (including HttpOnly ones like logged-in-sig) are sent automatically.
      // document.cookie misses HttpOnly cookies, which broke the old flow.
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "https://archive.org/account/s3.php", false);
            xhr.send();
            var html = xhr.responseText;
            var parser = new DOMParser();
            var doc = parser.parseFromString(html, "text/html");

            // Find S3 keys: 16-char alphanumeric values in input elements.
            // IA removed name="access"/name="secret" attributes, so we
            // match by value pattern. DOMParser docs need getAttribute
            // since .value is empty on non-live DOMs.
            function findKeys(d) {
              var allInputs = d.querySelectorAll("input");
              var keys = [];
              for (var i = 0; i < allInputs.length; i++) {
                var v = allInputs[i].getAttribute("value") || "";
                if (v.length === 16 && /^[A-Za-z0-9]+\$/.test(v)) {
                  keys.push(v);
                }
              }
              return keys;
            }

            var keys = findKeys(doc);
            if (keys.length < 2) {
              // No keys yet — generate them via the s3.php form.
              var xhr2 = new XMLHttpRequest();
              xhr2.open("POST", "https://archive.org/account/s3.php", false);
              xhr2.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
              xhr2.send("generateNewKeys=Generate+New+Keys&confirm=on");
              html = xhr2.responseText;
              doc = parser.parseFromString(html, "text/html");
              keys = findKeys(doc);
            }

            var access = keys.length > 0 ? keys[0] : "";
            var secret = keys.length > 1 ? keys[1] : "";
            var cookieStr = document.cookie;
            var user = cookieStr.split("; ")
              .find(function(c) { return c.startsWith("logged-in-user="); });
            var username = user ? user.split("=")[1] : "";
            return JSON.stringify({access: access, secret: secret, username: username});
          } catch(e) {
            return JSON.stringify({error: e.message});
          }
        })()
      ''');

      final rawString = result.toString();
      final cleanString = rawString.startsWith('"') && rawString.endsWith('"')
          ? rawString.substring(1, rawString.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\')
          : rawString;

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(cleanString) as Map<String, dynamic>;
      } catch (_) {
        return;
      }

      if (parsed.containsKey('error') || parsed.isEmpty) return;

      final access = parsed['access'] as String? ?? '';
      final secret = parsed['secret'] as String? ?? '';
      final username = Uri.decodeComponent(parsed['username'] as String? ?? '');

      // Get ALL cookies (including HttpOnly) via Android's native CookieManager.
      // document.cookie misses HttpOnly cookies like logged-in-sig which
      // IA requires for download auth.
      const channel = MethodChannel('com.caprado.romgi/open');
      final nativeCookies = await channel.invokeMethod<String>(
        'getWebViewCookies',
        {'url': 'https://archive.org'},
      ) ?? '';

      if (access.isEmpty || secret.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not retrieve Internet Archive credentials. '
              'Please try again.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final auth = ref.read(internetArchiveAuthProvider);
      final session = await auth.saveSessionFromKeys(
        username: username,
        accessKey: access,
        secretKey: secret,
        cookies: nativeCookies,
      );

      if (!mounted) return;

      ref.invalidate(iaLoggedInProvider);
      ref.invalidate(iaUsernameProvider);
      ref.invalidate(iaSessionStatusProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged in as ${session.username}'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      // Network/JS errors are recoverable — the user can retry.
    } finally {
      _exchangeInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internet Archive Login'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Column(
        children: [
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.lock,
                  size: 16,
                  color: _currentUrl.startsWith('https')
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // WebView
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
