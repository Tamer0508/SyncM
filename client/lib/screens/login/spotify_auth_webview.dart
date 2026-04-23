import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/api_service.dart';

class SpotifyAuthWebView extends StatefulWidget {
  final String authUrl;
  const SpotifyAuthWebView({Key? key, required this.authUrl}) : super(key: key);

  @override
  State<SpotifyAuthWebView> createState() => _SpotifyAuthWebViewState();
}

class _SpotifyAuthWebViewState extends State<SpotifyAuthWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spotify Login')),
      body: WebViewWidget(
        controller: _controller
          ..loadRequest(Uri.parse(widget.authUrl))
          ..setNavigationDelegate(NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.startsWith('myapp://callback')) {
                final uri = Uri.parse(request.url);
                final cookie = uri.queryParameters['cookie'] ?? '';
                final token = uri.queryParameters['token'];
                Navigator.of(context).pop({
                  'cookie': cookie,
                  'token': token,
                });
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          )),
      ),
    );
  }
}
