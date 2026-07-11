import 'package:flutter/material.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/friends/friend_requests_screen.dart';
import 'screens/friends/search_users_screen.dart';
import 'screens/session/create_session_screen.dart';
import 'screens/session/session_screen.dart';
import 'screens/session/session_results_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/player/now_playing.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/session/pick_playlist_screen.dart';
import 'screens/session/session_invites_screen.dart';

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/':
      return MaterialPageRoute(builder: (_) => const LoginScreen());
    case '/home':
      return MaterialPageRoute(builder: (_) => const HomeScreen());
    case '/friends':
      return MaterialPageRoute(builder: (_) => const FriendsScreen());
    case '/friends/requests':
      return MaterialPageRoute(builder: (_) => const FriendRequestsScreen());
    case '/friends/search':
      return MaterialPageRoute(builder: (_) => const SearchUsersScreen());
    case '/session/create':
      return MaterialPageRoute(builder: (_) => const CreateSessionScreen());
    case '/session/invites':
      return MaterialPageRoute(builder: (_) => const SessionInvitesScreen());
    case '/session':
      return MaterialPageRoute(
        builder: (_) => const SessionScreen(),
        settings: settings,
      );
    case '/session/results':
      return MaterialPageRoute(
        builder: (_) => const SessionResultsScreen(),
        settings: settings,
      );
    case '/profile':
      return MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
        settings: settings,
      );
    case '/settings':
      return MaterialPageRoute(builder: (_) => const SettingsScreen());
    case '/playlist/pick':
      return MaterialPageRoute(
        builder: (_) => const PickPlaylistScreen(),
        settings: settings,
      );
    case '/player':
      final args = settings.arguments as Map<String, dynamic>?;
      return PageRouteBuilder(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) {
          return NowPlayingScreen(
            title: args?['title'] as String?,
            artist: args?['artist'] as String?,
            artworkUrl: args?['artworkUrl'] as String?,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Slide transition from bottom
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      );
    default:
      return MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Unknown route')),
        ),
      );
  }
}