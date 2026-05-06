import 'dart:html' as html;
import 'package:flutter/material.dart';

// Заглушка WebView для веба — не используется
Widget buildSpotifyWebView(String authUrl) => const SizedBox.shrink();

// Реальный редирект для веба в той же вкладке
void redirectToUrl(String url) {
  html.window.location.href = url;
}