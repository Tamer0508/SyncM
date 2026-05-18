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
import 'theme.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'widgets/mini_player.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
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
        ChangeNotifierProvider(create: (_) => PlaybackProvider()),
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
          home: const _AuthGate(),
          onGenerateRoute: generateRoute,
          builder: (context, child) {
            return Scaffold(
              body: SafeArea(child: child ?? const SizedBox.shrink()),
              bottomNavigationBar: const MiniPlayer(),
            );
          },
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

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.restoreSavedAuth();

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

      final userId = auth.user?.id;
      if (userId != null) {
        final socket = SocketService();
        socket.init('https://syncm-production.up.railway.app', userId);
      }
    });
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
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}