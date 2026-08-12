import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'dart:async';
import 'dart:io';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';


import 'google_sign_stub.dart'
    if (dart.library.html) 'google_sign_web.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback onSignInSuccess;

  const GoogleSignInButton({super.key, required this.onSignInSuccess});

  bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return buildWebButton();
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: () =>
            _isWindows ? _handleWindowsSignIn(context) : _handleSignIn(context),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login), // цвет унаследуется от кнопки
            SizedBox(width: 8),
            Text('Войти через Google'), // цвет унаследуется от кнопки
          ],
        ),
      );
    }
  }

  Future<void> _handleWindowsSignIn(BuildContext context) async {
  try {
    final api = ApiService();
    final completer = Completer<Map<String, dynamic>?>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8181);
    debugPrint('Local server started on port 8181');

    final authUrl = Uri.parse(
      '${api.baseUrl}/auth/google-web?returnTo=http://localhost:8181/callback',
    );
    debugPrint('Opening URL: $authUrl');

    await launchUrl(authUrl, mode: LaunchMode.externalApplication);

    server.listen((request) async {
  final uri = request.requestedUri;
  final response = request.response;
  response.headers.set('Content-Type', 'text/html; charset=utf-8');
  response.write('<html><body><h2>Login successful! You can close this tab.</h2></body></html>');
  await response.close();
  await server.close();

  final cookie = uri.queryParameters['cookie'];
  final token = uri.queryParameters['token'];
  completer.complete({'cookie': cookie, 'token': token});
});

    final result = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () { server.close(); return null; },
    );

    debugPrint('Auth result: $result');

    if (result != null && context.mounted) {
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final token = result['token'] as String?;
  final cookie = result['cookie'] as String?;
  
  debugPrint('token: $token');
  debugPrint('cookie: $cookie');
  
  if (token != null && token.isNotEmpty) {
    auth.setCookie(token);
  } else if (cookie != null && cookie.isNotEmpty) {
    auth.setCookie(cookie);
  }
  
  await auth.fetchMe();
  debugPrint('isLoggedIn: ${auth.isLoggedIn}');
  
  if (auth.isLoggedIn && context.mounted) {
    Navigator.of(context).pushReplacementNamed('/home');
  }
}
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

      final googleAuth = account.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        if (context.mounted) {
          showAppNotification(context, message: 'Ошибка: не удалось получить ID токен от Google', type: NotificationType.error);
        }
        return;
      }

      final api = ApiService();
      final resp = await api.googleLogin(idToken);

      if (context.mounted) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final cookie = resp['cookie'] as String?;
        final user = resp['user'] as Map<String, dynamic>?;
        final issued = resp['authToken'] as String?;
        if (issued != null && issued.isNotEmpty) {
          auth.setCookie(issued);
        } else if (cookie != null && cookie.isNotEmpty) {
          auth.setCookie(cookie);
        }
        if (user != null) {
          auth.setUser(auth.userFromMap(user));
        }
        await auth.fetchMe();
        if (auth.isLoggedIn && context.mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
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