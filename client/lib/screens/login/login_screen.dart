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
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/ambient_background.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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
      if (e.toString().contains('init() has already been called')) {
        _googleInitDone = true;
        return;
      }
      rethrow;
    }
  }

  Future<void> _onGoogleSignInSuccess(GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken != null) {
      final api = ApiService();
      try {
        final resp = await api.googleLogin(idToken);
        final user = resp['user'] as Map<String, dynamic>?;
        if (user != null) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          auth.setUser(auth.userFromMap(user));
          final issued = resp['authToken'] as String?;
          if (issued != null && issued.isNotEmpty) auth.setCookie(issued);
          await auth.fetchMe();
          if (auth.isLoggedIn && mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        }
      } catch (e) {
        debugPrint('onGoogleSignInSuccess error: $e');
        if (mounted) {
          showError(context, e);
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
      await _onGoogleSignInSuccess(googleUser);
    } catch (e) {
      debugPrint('_signInWithGoogle error: $e');
      if (mounted) {
        showError(context, e);
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
    final colors = context.colors;
    final texts = context.texts;

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      // На планшете и в браузере форма во всю ширину читается
                      // тяжело: строка становится слишком длинной.
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Brand(),
                          const SizedBox(height: AppSpacing.xl),
                          _SignInCard(
                            onWebSignIn: _signInWithGoogle,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'Слушайте одну музыку одновременно — где бы вы ни были.',
                            textAlign: TextAlign.center,
                            style: texts.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: AppRadius.large,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.graphic_eq_rounded, size: 36, color: colors.onPrimaryContainer),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'SyncM',
          textAlign: TextAlign.center,
          style: texts.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Музыка для друзей',
          textAlign: TextAlign.center,
          style: texts.titleMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.onWebSignIn});

  final VoidCallback onWebSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.82),
        borderRadius: AppRadius.extraLarge,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Вход',
            style: texts.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Войдите через Google, чтобы создавать сессии и слушать музыку вместе.',
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          GoogleSignInButton(onSignInSuccess: () {}),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onWebSignIn,
            child: const Text('Войти через браузер'),
          ),
        ],
      ),
    );
  }
}

class _AuthWebView extends StatefulWidget {
  const _AuthWebView();

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