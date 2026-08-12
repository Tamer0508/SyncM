import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../utils/error_utils.dart';
import '../utils/notifications.dart';
import '../screens/profile/spotify_webview_screen.dart'
    if (dart.library.html) '../screens/profile/spotify_webview_stub.dart';

HttpServer? _oauthServer;

Future<void> stopSpotifyOauthServer() async {
  final server = _oauthServer;
  if (server == null) return;
  _oauthServer = null;
  try {
    await server.close(force: true);
  } catch (err) {
    debugPrint('Не удалось закрыть локальный сервер авторизации: $err');
  }
}

Future<void> connectSpotify(BuildContext context) async {
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final api = auth.api;

  if (kIsWeb) {
    final state =
        await api.createSpotifyLinkIntent(returnTo: Uri.base.origin);
    final webUrl = '${api.baseUrl}/auth/login?state=$state';
    redirectToUrl(webUrl);
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.windows) {
    HttpServer? server;
    try {
      if (_oauthServer != null) {
        try { await _oauthServer!.close(force: true); } catch (_) {}
        _oauthServer = null;
      }

      final completer = Completer<Map<String, dynamic>?>();
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, 8282, shared: true,
      );
      _oauthServer = server;

      final state = await api.createSpotifyLinkIntent(
          returnTo: 'http://localhost:8282/callback');
      final authUrl = Uri.parse('${api.baseUrl}/auth/login?state=$state');
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      server.listen((request) async {
        final uri = request.requestedUri;
        final response = request.response;
        response.headers.set('Content-Type', 'text/html; charset=utf-8');
        response.write('<html><body><h2>Spotify connected! You can close this tab.</h2></body></html>');
        await response.close();
        await server!.close(force: true);
        _oauthServer = null;
        if (!completer.isCompleted) {
          completer.complete({
            'token': uri.queryParameters['token'],
            'cookie': uri.queryParameters['cookie'],
          });
        }
      });
      final result = await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () async {
          try { await server?.close(force: true); } catch (_) {}
          _oauthServer = null;
          return null;
        },
      );
      if (result != null) {
        final token = result['token'] as String?;
        final cookie = result['cookie'] as String?;
        if (token != null && token.isNotEmpty) {
          auth.setCookie(token);
        } else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
        await auth.fetchMe();
        if (context.mounted) {
          showAppNotification(context, message: 'Spotify успешно подключён!', type: NotificationType.success);
        }
      }
    } catch (e) {
      // Гарантированно освобождаем порт при любой ошибке.
      try { await server?.close(force: true); } catch (_) {}
      _oauthServer = null;
      final msg = e.toString().contains('bind') || e.toString().contains('port')
          ? 'Не удалось начать подключение: предыдущая попытка ещё не завершилась. Подождите несколько секунд и попробуйте снова.'
          : 'Ошибка подключения: $e';
      if (context.mounted) showAppNotification(context, message: msg, type: NotificationType.error);
    }
    return;
  }

  // Android/iOS
  final state =
      await api.createSpotifyLinkIntent(returnTo: 'myapp://callback');
  final authUrl = '${api.baseUrl}/auth/login?state=$state';
  final result = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(builder: (_) => buildSpotifyWebView(authUrl)),
  );
  if (result != null) {
    final token = result['token'] as String?;
    final cookie = result['cookie'] as String?;
    if (token != null && token.isNotEmpty) {
      auth.setCookie(token);
    } else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
    await auth.fetchMe();
    if (context.mounted) {
      showAppNotification(context, message: 'Spotify успешно подключён!', type: NotificationType.success);
    }
  }
}

Future<void> disconnectSpotify(BuildContext context) async {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(Icons.link_off, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Text('Отключить Spotify', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
      content: const Text('Вы уверены, что хотите отключить Spotify аккаунт?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            try {
              final api = Provider.of<AuthProvider>(context, listen: false).api;
              await api.disconnectSpotify();
              final auth = Provider.of<AuthProvider>(context, listen: false);
              await auth.fetchMe();
              if (context.mounted) {
                showAppNotification(context, message: 'Spotify отключен', type: NotificationType.success);
              }
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Отключить'),
        ),
      ],
    ),
  );
}