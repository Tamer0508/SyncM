import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/error_utils.dart';
import '../utils/notifications.dart';
import 'oauth_loopback.dart';
import '../screens/profile/spotify_webview_screen.dart'
    if (dart.library.html) '../screens/profile/spotify_webview_stub.dart';

const int _oauthLoopbackPort = 8282;

Future<void> stopSpotifyOauthServer() => stopOAuthLoopback();

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

  if (defaultTargetPlatform == TargetPlatform.windows && supportsOAuthLoopback) {
    try {
      final result = await runOAuthLoopback(
        port: _oauthLoopbackPort,
        responseHtml:
            '<html><body><h2>Spotify подключён! Вкладку можно закрыть.</h2></body></html>',
        onServerReady: (redirectUri) async {
          final state = await api.createSpotifyLinkIntent(returnTo: redirectUri);
          final authUrl = Uri.parse('${api.baseUrl}/auth/login?state=$state');
          await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        },
      );

      if (result != null) {
        final token = result['token'];
        final cookie = result['cookie'];
        if (token != null && token.isNotEmpty) {
          auth.setCookie(token);
        } else if (cookie != null && cookie.isNotEmpty) {
          auth.setCookie(cookie);
        }
        await auth.fetchMe();
        if (context.mounted) {
          showAppNotification(context,
              message: 'Spotify подключён',
              type: NotificationType.success);
        }
      }
    } catch (e) {
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
    final error = result['error'] as String?;
    if (error != null && error.isNotEmpty) {
      if (context.mounted) {
        showAppNotification(context, message: error, type: NotificationType.error);
      }
      return;
    }

    final token = result['token'] as String?;
    final cookie = result['cookie'] as String?;
    if (token != null && token.isNotEmpty) {
      auth.setCookie(token);
    } else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
    await auth.fetchMe();
    if (context.mounted) {
      showAppNotification(context, message: 'Spotify подключён', type: NotificationType.success);
    }
  }
}

Future<void> disconnectSpotify(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.link_off_rounded, color: ctx.colors.error),
      title: const Text('Отключить Spotify?'),
      content: const Text(
        'Плейлисты и совместное прослушивание перестанут работать, '
        'пока вы не подключите его снова.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: ctx.colors.error,
            foregroundColor: ctx.colors.onError,
          ),
          child: const Text('Отключить'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.api.disconnectSpotify();
    await auth.fetchMe();
    if (context.mounted) {
      showAppNotification(
        context,
        message: 'Spotify отключён',
        type: NotificationType.success,
      );
    }
  } catch (err) {
    if (context.mounted) showError(context, err);
  }
}