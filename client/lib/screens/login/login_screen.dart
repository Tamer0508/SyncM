import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
Future<void>? _googleInitFuture;
bool _googleInitDone = false;

class _LoginScreenState extends State<LoginScreen> {
  bool _handledAuth = false;
  StreamSubscription? _googleAuthSubscription;

  @override
  void initState() {
    super.initState();
    _googleAuthSubscription = GoogleSignIn.instance.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _onGoogleSignInSuccess(event.user);
      }
    });
    _initializeGoogleSignIn();

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

  Future<void> _initializeGoogleSignIn() async {
    if (_googleInitDone) return;
    _googleInitFuture ??= GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? googleClientId : null,
    );
    try {
      await _googleInitFuture;
      _googleInitDone = true;
    } catch (e) {
      // On web hot restarts, plugin can already be initialized.
      if (e.toString().contains('init() has already been called')) {
        _googleInitDone = true;
        return;
      }
      rethrow;
    }
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
          auth.setCookie(user['id']);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.colorScheme.background, theme.colorScheme.primary.withOpacity(0.08)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Новый дизайн', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 18),
                      Text('SyncM', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: theme.textTheme.bodyLarge?.color)),
                      const SizedBox(height: 10),
                      Text(
                        'Синхронизируй музыку, треки и друзей в едином приложении с новым чистым интерфейсом.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8), height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 12,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Начать работу', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Text(
                          'Войдите с Google, чтобы открыть новый поток музыки и активных сессий.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75), height: 1.6),
                        ),
                        const SizedBox(height: 24),
                        GoogleSignInButton(onSignInSuccess: () {}),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: _signInWithGoogle,
                          child: const Text('Использовать Google с веб-авторизацией'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 88,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Яркая палитра', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text('Белый фон, серые тексты и яркие акценты', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.75))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
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
    _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    final authUrl = Uri.parse('${api.baseUrl}/auth/login?returnTo=myapp://callback');

    return Scaffold(
      appBar: AppBar(title: const Text('Spotify Login')),
      body: WebViewWidget(
        controller: _controller
          ..loadRequest(authUrl)
          ..setNavigationDelegate(NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.startsWith('myapp://callback')) {
                final uri = Uri.parse(request.url);
                final cookie = uri.queryParameters['cookie'] ?? '';
                Navigator.of(context).pop({
                  'cookie': cookie,
                  'needFetch': true,
                });
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          )),
      ),
    );
  }
}
