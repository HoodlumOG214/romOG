import 'package:flutter/material.dart';
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

            // Check if we've reached the account page (successful login)
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
      final cookieResult = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );

      // "name1=value1; name2=value2"
      final cookieMap = <String, String>{};
      final rawString = cookieResult.toString();
      final cleanString = rawString.startsWith('"') && rawString.endsWith('"')
          ? rawString.substring(1, rawString.length - 1)
          : rawString;

      for (final pair in cleanString.split('; ')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          cookieMap[pair.substring(0, idx)] = pair.substring(idx + 1);
        }
      }

      // Need the IA session cookies to bootstrap the S3-key fetch.
      final user = cookieMap['logged-in-user'];
      if (user == null || user.isEmpty) return;

      final auth = ref.read(internetArchiveAuthProvider);
      final session = await auth.completeLoginFromCookies(cookieMap);

      if (!mounted) return;

      if (session == null) {
        // Login succeeded but s3.php didn't yield keys; let the user retry.
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
