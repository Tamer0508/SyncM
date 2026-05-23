import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

import 'google_sign_stub.dart'
    if (dart.library.html) 'google_sign_web.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback onSignInSuccess;

  const GoogleSignInButton({super.key, required this.onSignInSuccess});

  bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (kIsWeb) {
      return buildWebButton();
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: theme.colorScheme.primary,
        ),
        onPressed: () => _isWindows ? _handleWindowsSignIn(context) : _handleSignIn(context),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login, color: Colors.white),
            SizedBox(width: 8),
            Text('Войти через Google', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
  }

  // На Windows — открываем браузер с Google OAuth
  Future<void> _handleWindowsSignIn(BuildContext context) async {
    try {
      final api = ApiService();
      // Используем бэкенд Google auth endpoint
      // После авторизации бэкенд вернёт токен через redirect
      final authUrl = Uri.parse(
        '${api.baseUrl}/auth/google-web?returnTo=syncm://auth-callback',
      );

      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть браузер')),
          );
        }
      }
    } catch (e) {
      print('Windows Google Sign-In error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка входа: $e')),
        );
      }
    }
  }

  // На мобильных — через Google Sign In SDK
  Future<void> _handleSignIn(BuildContext context) async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: '874254630560-14r27kn6ken47fk2g4tffmf8s22co6eh.apps.googleusercontent.com',
      );

      final account = await GoogleSignIn.instance.authenticate();
      if (account == null) return;

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось получить токен Google')),
          );
        }
        return;
      }

      final api = ApiService();
      final resp = await api.googleLogin(idToken);

      if (context.mounted) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final cookie = resp['cookie'] as String?;
        final user = resp['user'] as Map<String, dynamic>?;
        if (cookie != null) auth.setCookie(cookie);
        if (user != null) {
          auth.setUser(auth.userFromMap(user));
          auth.setCookie(user['id'] as String);
        }
        await auth.fetchMe();
        if (auth.isLoggedIn && context.mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }

      onSignInSuccess();
    } catch (e) {
      print('Google Sign-In error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка входа: $e')),
        );
      }
    }
  }
}