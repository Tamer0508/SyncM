import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/web_redirect.dart';
import '../../utils/web_auth_fetch.dart';
import '../../services/api_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../providers/auth_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../login/google_sign.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

class _LoginScreenState extends State<LoginScreen> {
  bool _handledAuth = false;
  bool _googleInitialized = false;
  StreamSubscription? _googleAuthSubscription;

  @override
  void initState() {
    super.initState();
    _initializeGoogleSignIn();
    _listenToGoogleAuthEvents();

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_handledAuth) return;
        final done = Uri.base.queryParameters['auth_done'];
        if (done != null) {
          _handledAuth = true;
          try {
            final api = ApiService();
            final base = api.baseUrl;
            final data = await fetchMeWithCredentials(base);
            if (data != null) {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final user = auth.userFromMap(data);
              auth.setUser(user);
              auth.setCookie(user.id);
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/home');
              }
            }
          } catch (_) {}
        }
      });
    }
  }

    void _listenToGoogleAuthEvents() {
      GoogleSignIn.instance.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _onGoogleSignInSuccess(event.user);
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        print('User signed out');
      }
    });
  }

    Future<void> _initializeGoogleSignIn() async {
      if (_googleInitialized) return;
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? googleClientId : null,
     );
      _googleInitialized = true;

      _googleAuthSubscription = GoogleSignIn.instance.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _onGoogleSignInSuccess(event.user);
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          print('User signed out');
        }
      });
    }

    Future<void> _onGoogleSignInSuccess(GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken != null) {
      final api = ApiService();
      try {
        final resp = await api.googleLogin(idToken);
        final user = resp['user'] as Map<String, dynamic>?;
        if (user != null) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          auth.setUser(auth.userFromMap(user));
          auth.setCookie(user['id']); // Сохраняем userId, а не cookie
          await auth.fetchMe();
          if (auth.isLoggedIn && mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Google Sign-In error: $e')),
          );
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) return;
      await _onGoogleSignInSuccess(googleUser);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _googleAuthSubscription?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Авторизация')),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050505), Color(0xFF181818)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Card(
            color: Colors.black87,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 10,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Выберите способ входа', style: TextStyle(fontSize: 20, color: Colors.white)),
                  const SizedBox(height: 12),
                  GoogleSignInButton(onSignInSuccess: () {
                    // Этот колбэк будет вызван после успешного входа через Google
                    // Здесь можно выполнить дополнительные действия, если нужно
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthWebView extends StatefulWidget {
  const _AuthWebView({Key? key}) : super(key: key);

  @override
  State<_AuthWebView> createState() => _AuthWebViewState();
}

class _AuthWebViewState extends State<_AuthWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    // Передаем кастомную схему в returnTo
    final authUrl =
        Uri.parse('${api.baseUrl}/auth/login?returnTo=myapp://callback');

    return Scaffold(
      appBar: AppBar(title: const Text('Spotify Login')),
      body: WebViewWidget(
        controller: _controller
          ..loadRequest(authUrl)
          ..setNavigationDelegate(NavigationDelegate(
            // ПЕРЕХВАТЫВАЕМ РЕДИРЕКТ
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.startsWith('myapp://callback')) {
                final uri = Uri.parse(request.url);
                final cookie = uri.queryParameters['cookie'] ?? '';

                // Закрываем WebView и отдаем cookie
                Navigator.of(context).pop({
                  'cookie': cookie,
                  'needFetch': true, // флаг, что нужно запросить данные юзера
                });
                return NavigationDecision.prevent; // Отменяем загрузку страницы
              }
              return NavigationDecision.navigate;
            },
          )),
      ),
    );
  }
}
