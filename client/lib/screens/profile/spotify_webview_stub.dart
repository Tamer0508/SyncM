import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// Заглушка WebView для веба — не используется
Widget buildSpotifyWebView(String authUrl) => const SizedBox.shrink();

// Реальный редирект для веба в той же вкладке
void redirectToUrl(String url) {
  web.window.location.href = url;
}
