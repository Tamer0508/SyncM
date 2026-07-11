import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/session_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/theme_provider.dart';
import 'services/socket_service.dart';
import 'services/api_service.dart';
import 'theme.dart';
import 'utils/app_globals.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'widgets/app_shell.dart';

void main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, FriendsProvider>(
          create: (_) => FriendsProvider(),
          update: (_, auth, friends) {
            if (auth.cookie != null) {
              friends?.syncCookie(auth.cookie!);
            }
            return friends ?? FriendsProvider();
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, SessionProvider>(
          create: (_) => SessionProvider(),
          update: (_, auth, session) {
            if (auth.cookie != null) {
              session?.syncCookie(auth.cookie!);
            }
            return session ?? SessionProvider();
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, PlaybackProvider>(
          create: (_) => PlaybackProvider(),
          update: (_, auth, playback) {
            final pb = playback ?? PlaybackProvider();
            if (auth.cookie != null) {
              final api = ApiService();
              api.setCookie(auth.cookie!);
              pb.setApiService(api);
            }
            return pb;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<SocketService>.value(value: SocketService()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'SyncM',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeProvider.themeMode,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          builder: (context, child) => AppShell(child: child ?? const SizedBox.shrink()),
          home: const _AuthGate(),
          onGenerateRoute: generateRoute,
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({Key? key}) : super(key: key);

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.restoreSavedAuth();

      if (kIsWeb) {
        final uri = Uri.base;
        final cookie = uri.queryParameters['cookie'];
        final token = uri.queryParameters['token'];
        final authDone = uri.queryParameters['auth_done'];

        if (authDone != null) {
          if (token != null && token.isNotEmpty) {
            auth.setCookie(Uri.decodeComponent(token));
          } else if (cookie != null && cookie.isNotEmpty) {
            auth.setCookie(Uri.decodeComponent(cookie));
          }
        }
      }

      await auth.fetchMe();
      _ensureSocketInitialized(auth);
    });
  }

  // Инициализирует сокет и realtime-провайдеры, когда пользователь известен.
  // РАНЬШЕ это было только в initState — если userId появлялся ПОЗЖЕ (свежая
  // установка: сначала логин, потом userId), сокет не поднимался до перезахода,
  // из-за чего не работали онлайн-статусы и приглашения в реальном времени.
  // Теперь вызывается и после логина (из build), защита от повторного запуска
  // внутри.
  bool _socketInitialized = false;
  void _ensureSocketInitialized(AuthProvider auth) {
    if (_socketInitialized) return;
    final userId = auth.user?.id;
    if (userId == null) return;
    _socketInitialized = true;
    final socket = SocketService();
    socket.init('https://syncm-production.up.railway.app', userId);
    Provider.of<FriendsProvider>(context, listen: false).init(socket);
    Provider.of<SessionProvider>(context, listen: false).init(socket);
    Provider.of<SessionProvider>(context, listen: false).fetchInvites();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Шаг 1 (жизненный цикл): при СВОРАЧИВАНИИ (paused/inactive/hidden) ничего
    // не рвём — сокет держится сам, сколько позволит ОС, и участник остаётся
    // в сессии. При ВОЗВРАТЕ (resumed) освежаем часы и ресинкаем состояние
    // сессии, чтобы мгновенно вернуться в синхру после паузы/блокировки экрана.
    if (state == AppLifecycleState.resumed) {
      SocketService().resyncNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, __) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.isLoggedIn) {
          // Пользователь залогинен — поднимаем сокет, если он ещё не поднят
          // (важно для свежего логина, когда userId появился после initState).
          // Откладываем на post-frame, чтобы не вызывать провайдеры во время build.
          if (!_socketInitialized && auth.user?.id != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensureSocketInitialized(auth);
            });
          }
          return const HomeScreen();
        }
        // Не залогинен (в т.ч. после логаута) — сбрасываем флаг, чтобы при
        // следующем входе сокет поднялся заново (возможно, другим аккаунтом).
        _socketInitialized = false;
        return const LoginScreen();
      },
    );
  }
}