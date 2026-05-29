import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/web_auth_fetch.dart';
import '../../services/api_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../providers/auth_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../login/google_sign.dart';
import '../../utils/notifications.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
Future<void>? _googleInitFuture;
bool _googleInitDone = false;

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground({Key? key}) : super(key: key);

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with TickerProviderStateMixin {
  late final AnimationController _circlesController;
  late final AnimationController _particlesController;

  final _random = Random(42);
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _circlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();

    _particles = List.generate(60, (_) => _Particle(_random));
  }

  @override
  void dispose() {
    _circlesController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final circleColors = isDark
        ? [
            const Color(0xFF2D3348).withOpacity(0.45),
            const Color(0xFF3A2D44).withOpacity(0.35),
            const Color(0xFF1E3A4A).withOpacity(0.35),
          ]
        : [
            const Color(0xFFE8EEFF).withOpacity(0.5),
            const Color(0xFFFFE8EE).withOpacity(0.4),
            const Color(0xFFE0F0FF).withOpacity(0.4),
          ];

    final particleBaseColor = isDark
        ? const Color(0xFFB0C0D0).withOpacity(0.45)
        : const Color(0xFF8090B0).withOpacity(0.28);

    final lineColor = isDark
        ? const Color(0xFFB0C0D0).withOpacity(0.15)
        : const Color(0xFF8090B0).withOpacity(0.12);

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _circlesController,
            builder: (_, __) => CustomPaint(
              painter: _CircleLayerPainter(
                animationValue: _circlesController.value,
                colors: circleColors,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _particlesController,
            builder: (_, __) => CustomPaint(
              painter: _ParticleNetworkPainter(
                animationValue: _particlesController.value,
                particles: _particles,
                particleColor: particleBaseColor,
                lineColor: lineColor,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _Particle {
  double x, y;
  final double speed;
  final double radius;
  final double opacity;
  final double phase;
  final double connectionRadius;

  _Particle(Random random)
      : x = random.nextDouble(),
        y = random.nextDouble(),
        speed = 0.08 + random.nextDouble() * 0.06,
        radius = 1.4 + random.nextDouble() * 2.8,
        opacity = 0.35 + random.nextDouble() * 0.45,
        phase = random.nextDouble() * 2 * pi,
        connectionRadius = 0.12 + random.nextDouble() * 0.14;
}

class _ParticleNetworkPainter extends CustomPainter {
  final double animationValue;
  final List<_Particle> particles;
  final Color particleColor;
  final Color lineColor;

  _ParticleNetworkPainter({
    required this.animationValue,
    required this.particles,
    required this.particleColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final particlePaint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final positions = <Offset>[];
    for (final p in particles) {
      final dx = (animationValue * p.speed * 2 * pi + p.phase);
      final dy = (animationValue * p.speed * 3 * pi + p.phase * 1.7);
      final nx = (p.x + 0.60 * sin(dx)) % 1.0;
      final ny = (p.y + 0.60 * cos(dy)) % 1.0;
      positions.add(Offset(nx * size.width, ny * size.height));
    }

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        final maxDist = size.width * particles[i].connectionRadius;
        if (d < maxDist) {
          final opacity = (1 - d / maxDist) * 0.4;
          linePaint.color = lineColor.withOpacity(opacity.clamp(0.0, 1.0));
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }

    for (int i = 0; i < particles.length; i++) {
      particlePaint.color = particleColor.withOpacity(particles[i].opacity);
      canvas.drawCircle(positions[i], particles[i].radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleNetworkPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.particleColor != particleColor ||
      oldDelegate.lineColor != lineColor;
}

class _CircleLayerPainter extends CustomPainter {
  final double animationValue;
  final List<Color> colors;

  _CircleLayerPainter({
    required this.animationValue,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55);

    final positions = [
      Offset(size.width * 0.25, size.height * 0.3),
      Offset(size.width * 0.75, size.height * 0.65),
      Offset(size.width * 0.5, size.height * 0.5),
    ];

    final radii = [
      160.0 + 40 * sin(animationValue * 2 * pi),
      200.0 + 60 * cos(animationValue * 2 * pi + 1),
      180.0 + 50 * sin(animationValue * 2 * pi + 2),
    ];

    for (int i = 0; i < positions.length; i++) {
      final t = animationValue * 2 * pi;
      final cx = positions[i].dx + 30 * sin(t + i);
      final cy = positions[i].dy + 30 * cos(t + i * 1.3);
      paint.color = colors[i % colors.length];
      canvas.drawCircle(Offset(cx, cy), radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircleLayerPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

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
        print('onGoogleSignInSuccess error: $e');
        if (mounted) {
          showAppNotification(context, message: 'Google Sign-In error: $e', type: NotificationType.error);
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
      print('_signInWithGoogle error: $e');
      if (mounted) {
        showAppNotification(context, message: 'Google Sign-In error: $e', type: NotificationType.error);
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
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF0F1119)
        : const Color(0xFFF5F6FA);

    final cardColor = isDark
        ? theme.colorScheme.surface.withOpacity(0.85)
        : Colors.white.withOpacity(0.75);

    final shadowColor = isDark
        ? Colors.black.withOpacity(0.4)
        : const Color(0xFFB0B8C0).withOpacity(0.2);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          const Positioned.fill(child: _AnimatedBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Музыка для друзей',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'SyncM',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                          color: cardColor,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Начать работу',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Войдите с Google, чтобы слушать музыку вместе с друзьями.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                                    height: 1.6,
                                  ),
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
                                constraints: const BoxConstraints(minHeight: 88),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: shadowColor,
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Глубокая синхронизация',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: theme.textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Музыка и сессии синхронизируются в реальном времени, находясь в разных местах.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                                      ),
                                    ),
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
                );
              },
            ),
          ),
        ],
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