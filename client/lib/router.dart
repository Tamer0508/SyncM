import 'package:flutter/material.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/friends/friend_requests_screen.dart';
import 'screens/friends/search_users_screen.dart';
import 'screens/session/create_session_screen.dart';
import 'screens/session/session_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/player/now_playing.dart';


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
    case '/session':
      return MaterialPageRoute(builder: (_) => const SessionScreen());
    case '/profile':
      return MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
        settings: settings,
      );
    case '/player':
      final args = settings.arguments as Map<String, dynamic>?;
      return MaterialPageRoute(
          builder: (_) => NowPlayingScreen(
                title: args?['title'] as String?,
                artist: args?['artist'] as String?,
                artworkUrl: args?['artworkUrl'] as String?,
              ));
    default:
      return MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Unknown route')),
        ),
      );
  }
}
