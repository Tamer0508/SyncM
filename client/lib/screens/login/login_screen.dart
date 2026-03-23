import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            // Open WebView for OAuth flow
            final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AuthWebView()));
            if (result is Map<String, dynamic> && result.containsKey('payload')) {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              try {
                final payload = Map<String, dynamic>.from(result['payload'] as Map);
                final user = auth.userFromMap(payload);
                auth.setUser(user);
                final cookie = (result['cookie'] ?? '') as String;
                if (cookie.isNotEmpty) auth.setCookie(cookie);
              } catch (e) {
                await Provider.of<AuthProvider>(context, listen: false).fetchMe();
              }
            } else {
              await Provider.of<AuthProvider>(context, listen: false).fetchMe();
            }
          },
          child: const Text('Login with Spotify'),
        ),
      ),
    );
  }
}

class _AuthWebView extends StatefulWidget {
  const _AuthWebView({Key? key}) : super(key: key);

  @override
  State<_AuthWebView> createState() => _AuthWebViewState();
}

class _AuthWebViewState extends State<_AuthWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final authUrl = Uri.parse('http://10.0.2.2:3000/auth/login');

    return Scaffold(
      appBar: AppBar(title: const Text('Spotify Login')),
      body: WebViewWidget(
        controller: _controller
          ..loadRequest(authUrl)
          ..setNavigationDelegate(NavigationDelegate(
            onPageFinished: (url) async {
              if (url.contains('/auth/callback')) {
                try {
                  final raw = await _controller.runJavaScriptReturningResult('document.body.innerText');
                  String text;
                  if (raw is String) {
                    text = raw;
                  } else if (raw is List && raw.isNotEmpty) {
                    text = raw.join();
                  } else {
                    text = raw.toString();
                  }

                  text = text.trim();
                  // remove surrounding quotes if present
                  if ((text.startsWith('\"') && text.endsWith('\"')) || (text.startsWith('\'') && text.endsWith('\''))) {
                    text = text.substring(1, text.length - 1);
                  }

                    final Map<String, dynamic> data = json.decode(text) as Map<String, dynamic>;
                    // try to grab document.cookie too
                    String cookie = '';
                    try {
                      final rawCookie = await _controller.runJavaScriptReturningResult("document.cookie");
                      if (rawCookie is String) cookie = rawCookie;
                      if (rawCookie is List && rawCookie.isNotEmpty) cookie = rawCookie.join();
                    } catch (_) {}

                    Navigator.of(context).pop({'payload': (data['user'] ?? data), 'cookie': cookie});
                } catch (e) {
                  Navigator.of(context).pop();
                }
              }
            },
            onNavigationRequest: (req) {
              return NavigationDecision.navigate;
            },
          )),
      ),
    );
  }
}
