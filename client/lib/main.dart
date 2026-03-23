import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/session_provider.dart';
import 'providers/playback_provider.dart';
import 'widgets/player_bar.dart';
import 'theme.dart';

void main() {
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
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => PlaybackProvider()),
      ],
      child: MaterialApp(
        title: 'SyncM',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        initialRoute: '/',
        onGenerateRoute: generateRoute,
        builder: (context, child) {
          // Wrap navigator content so we can show a persistent mini-player
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
