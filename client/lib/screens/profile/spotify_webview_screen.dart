import '../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildSpotifyWebView(String authUrl) {
  return _SpotifyWebView(authUrl: authUrl);
}

void redirectToUrl(String url) {}

class _SpotifyWebView extends StatefulWidget {
  final String authUrl;
  const _SpotifyWebView({required this.authUrl});

  @override
  State<_SpotifyWebView> createState() => _SpotifyWebViewState();
}

class _SpotifyWebViewState extends State<_SpotifyWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url.startsWith('myapp://callback')) {
            final uri = Uri.parse(request.url);
            Navigator.of(context).pop({
              'cookie': uri.queryParameters['cookie'] ?? '',
              'token': uri.queryParameters['token'] ?? '',
              'error': uri.queryParameters['error'],
            });
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.of(context).spotifyWebviewTitle)),
      body: WebViewWidget(controller: _controller),
    );
  }
}