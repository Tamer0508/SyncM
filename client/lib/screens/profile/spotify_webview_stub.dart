import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildSpotifyWebView(String authUrl) => const SizedBox.shrink();

void redirectToUrl(String url) {
  web.window.location.href = url;
}
