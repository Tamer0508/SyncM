import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/session_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/playlists_provider.dart';
import 'providers/appearance_provider.dart';
import 'providers/theme_provider.dart';
import 'services/socket_service.dart';
import 'services/api_service.dart';
import 'theme.dart';
import 'config.dart';
import 'utils/image_cache.dart';
import 'utils/local_store.dart';
import 'utils/artwork_color_store.dart';
import 'utils/app_globals.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalStore.init();

  AppImageCache.configure();

  ArtworkColorStore.restore();

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
        ChangeNotifierProxyProvider<AuthProvider, PlaylistsProvider>(
          create: (_) => PlaylistsProvider(),
          update: (_, auth, playlists) {
            if (auth.cookie != null) {
              playlists?.syncCookie(auth.cookie!);
            }
            return playlists ?? PlaylistsProvider();
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
        ChangeNotifierProvider(create: (_) => AppearanceProvider()),
        Provider<SocketService>.value(value: SocketService()),
      ],
      child: Consumer2<ThemeProvider, AppearanceProvider>(
        builder: (context, themeProvider, appearance, _) => MaterialApp(
          title: 'SyncM',
          theme: _ThemeCache.of(
            brightness: Brightness.light,
            accent: appearance.accent,
            compact: appearance.compact,
            reduceMotion: appearance.reduceMotion,
          ),
          darkTheme: _ThemeCache.of(
            brightness: Brightness.dark,
            accent: appearance.accent,
            compact: appearance.compact,
            reduceMotion: appearance.reduceMotion,
          ),
          themeMode: themeProvider.themeMode,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(appearance.textScale),
                ).clamp(minScaleFactor: 0.8, maxScaleFactor: 1.6),
              ),
              child: AppLayoutScope(
                child: AppShell(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
          home: const _AuthGate(),
          onGenerateRoute: generateRoute,
        ),
      ),
    );
  }
}

class _ThemeCache {
  const _ThemeCache._();

  static final Map<String, ThemeData> _themes = {};

  static ThemeData of({
    required Brightness brightness,
    required AccentColor accent,
    required bool compact,
    required bool reduceMotion,
  }) {
    final key = '${brightness.name}:${accent.name}:$compact:$reduceMotion';
    return _themes.putIfAbsent(
      key,
      () => AppTheme.build(
        brightness: brightness,
        accent: accent,
        compact: compact,
        reduceMotion: reduceMotion,
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
            auth.setCookie(token);
          } else if (cookie != null && cookie.isNotEmpty) {
            auth.setCookie(Uri.decodeComponent(cookie));
          }
        }
      }

      await auth.fetchMe();
      _ensureSocketInitialized(auth);
    });
  }

  bool _socketInitialized = false;
  void _ensureSocketInitialized(AuthProvider auth) {
    if (_socketInitialized) return;

    final token = auth.cookie ?? '';
    debugPrint('[SocketGate] user=${auth.user?.id} длинаТокена=${token.length}');

    if (auth.user?.id == null) {
      debugPrint('[SocketGate] пользователь ещё не загружен — ждём');
      return;
    }
    if (!kIsWeb && token.isEmpty) {
      debugPrint('[SocketGate] ТОКЕНА НЕТ — сокет не создаётся');
      return;
    }

    _socketInitialized = true;
    final socket = SocketService();
    socket.init(Config.baseUrl, token);
    Provider.of<FriendsProvider>(context, listen: false).init(socket);
    Provider.of<SessionProvider>(context, listen: false).init(socket);
    Provider.of<SessionProvider>(context, listen: false).fetchInvites();
  }

  void _resetSessionState() {
    try {
      context.read<PlaybackProvider>().resetForLogout();
    } catch (err) {
      debugPrint('Не удалось остановить воспроизведение при выходе: $err');
    }
    SocketService().disconnect();
    try {
      context.read<SessionProvider>().clear();
      context.read<FriendsProvider>().clear();
    } catch (err) {
      debugPrint('Не удалось очистить списки при выходе: $err');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SocketService().resyncNow();

      if (mounted) {
        context.read<PlaybackProvider>().refreshAfterResume();
      }
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
        if (auth.loading && !auth.isLoggedIn) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.isLoggedIn) {
          if (!_socketInitialized && auth.user?.id != null && (kIsWeb || (auth.cookie ?? '').isNotEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensureSocketInitialized(auth);
            });
          }
          return const HomeScreen();
        }
        if (_socketInitialized) {
          _socketInitialized = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _resetSessionState();
          });
        }
        return const LoginScreen();
      },
    );
  }
}