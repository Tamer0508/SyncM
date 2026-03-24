import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';


// Импорт WebView только для мобильных
import 'package:webview_flutter/webview_flutter.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            if (kIsWeb) {
              // На вебе — открываем браузер
              final url = Uri.parse('https://syncm-production.up.railway.app/auth/login');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            } else {
              // На мобильном — WebView
              final result = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _AuthWebView()),
              );
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
              }
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final authUrl = Uri.parse(
      'https://syncm-production.up.railway.app/auth/login',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Spotify Login')),
      body: WebViewWidget(
        controller: _controller
          ..loadRequest(authUrl)
          ..setNavigationDelegate(NavigationDelegate(
            onPageFinished: (url) async {
              if (url.contains('/auth/callback')) {
                try {
                  final raw = await _controller
                      .runJavaScriptReturningResult('document.body.innerText');
                  String text = raw.toString().trim();
                  if ((text.startsWith('"') && text.endsWith('"'))) {
                    text = text.substring(1, text.length - 1);
                  }
                  final Map<String, dynamic> data =
                      json.decode(text) as Map<String, dynamic>;
                  String cookie = '';
                  try {
                    final rawCookie = await _controller
                        .runJavaScriptReturningResult('document.cookie');
                    cookie = rawCookie.toString();
                  } catch (_) {}
                  Navigator.of(context).pop({
                    'payload': (data['user'] ?? data),
                    'cookie': cookie,
                  });
                } catch (e) {
                  Navigator.of(context).pop();
                }
              }
            },
          )),
      ),
    );
  }
}
