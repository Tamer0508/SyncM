import '../../utils/app_globals.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/oauth_loopback.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';


import 'google_sign_stub.dart'
    if (dart.library.html) 'google_sign_web.dart';

const int _googleLoopbackPort = 8181;

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback onSignInSuccess;

  const GoogleSignInButton({super.key, required this.onSignInSuccess});

  bool get _isWindows =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      supportsOAuthLoopback;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return buildWebButton();
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
        ),
        onPressed: () =>
            _isWindows ? _handleWindowsSignIn(context) : _handleSignIn(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login), // цвет унаследуется от кнопки
            SizedBox(width: 8),
            Text(L.of(context).loginGoogle), // цвет унаследуется от кнопки
          ],
        ),
      );
    }
  }

  Future<void> _handleWindowsSignIn(BuildContext context) async {
    try {
      final api = ApiService();

      final result = await runOAuthLoopback(
        port: _googleLoopbackPort,
        responseHtml:
            '<html><body><h2>${appL10n?.loginDoneCloseTab ?? 'Вход выполнен! Вкладку можно закрыть.'}</h2></body></html>',
        onServerReady: (redirectUri) async {
          final authUrl = Uri.parse(
            '${api.baseUrl}/auth/google-web?returnTo=$redirectUri',
          );
          await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        },
      );

      if (result == null || !context.mounted) return;

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = result['token'];
      final cookie = result['cookie'];

      if (token != null && token.isNotEmpty) {
        auth.setCookie(token);
      } else if (cookie != null && cookie.isNotEmpty) {
        auth.setCookie(cookie);
      }

      await auth.fetchMe();
    } catch (e) {
      debugPrint('Windows Google Sign-In error: $e');
      if (context.mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _handleSignIn(BuildContext context) async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: '874254630560-14r27kn6ken47fk2g4tffmf8s22co6eh.apps.googleusercontent.com',
      );

      final account = await GoogleSignIn.instance.authenticate();

      if (account.authentication.idToken == null && context.mounted) {
        showAppNotification(
          context,
          message: L.of(context).loginGoogleNoToken,
          type: NotificationType.error,
        );
        return;
      }

      onSignInSuccess();
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (context.mounted) {
        showError(context, e);
      }
    }
  }
}