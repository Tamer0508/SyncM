import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/session_provider.dart';
import 'providers/playback_provider.dart';
import 'widgets/player_bar.dart';
import 'theme.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';

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
        ChangeNotifierProvider(create: (_) => PlaybackProvider()),
      ],
      child: MaterialApp(
        title: 'SyncM',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
        onGenerateRoute: generateRoute,
        builder: (context, child) {
          return Scaffold(
            body: SafeArea(child: child ?? const SizedBox.shrink()),
            bottomNavigationBar: Consumer<PlaybackProvider>(
              builder: (ctx, pb, _) {
                if (pb.currentTrack == null) return const SizedBox.shrink();
                final track = pb.currentTrack!;
                return SizedBox(
                  height: 76,
                  child: PlayerBar(
                    title: track['title'] ?? '',
                    artist: track['artist'] ?? '',
                    isPlaying: pb.isPlaying,
                    onPlayPause: () => pb.togglePlay(),
                  ),
                );
              },
            ),
          );
        },
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

    if (kIsWeb) {
      final uri = Uri.base;
      final cookie = uri.queryParameters['cookie'];
      final token = uri.queryParameters['token'];
      final authDone = uri.queryParameters['auth_done'];

      if (authDone != null) {
        if (token != null && token.isNotEmpty) {
          // userId передан напрямую
          auth.setCookie(Uri.decodeComponent(token));
        } else if (cookie != null && cookie.isNotEmpty) {
          // передан cookie — используем как есть для сессии
          auth.setCookie(Uri.decodeComponent(cookie));
        }
      }
    }

    await auth.fetchMe();
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