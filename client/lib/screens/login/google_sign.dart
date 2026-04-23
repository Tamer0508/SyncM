import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Импортируем web-реализацию ТОЛЬКО для веба
import 'package:google_sign_in_web/web_only.dart' as web;

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback onSignInSuccess;

  const GoogleSignInButton({super.key, required this.onSignInSuccess});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // На вебе рендерим специальную кнопку Google
      return web.renderButton();
    } else {
      // На других платформах оставляем обычную кнопку
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: Colors.blue,
        ),
        onPressed: _handleSignIn,
        child: const Text('Войти через Google'),
      );
    }
  }

  Future<void> _handleSignIn() async {
    try {
      // Для мобильных платформ используем стандартный метод authenticate
      await GoogleSignIn.instance.authenticate();
      // Успешный вход, вызываем колбэк
      onSignInSuccess();
    } catch (e) {
      // Обработка ошибок входа
      print('Google Sign-In error: $e');
    }
  }
}