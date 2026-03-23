import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/session_provider.dart';

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
      ],
      child: MaterialApp(
        title: 'SyncM',
        theme: ThemeData(primarySwatch: Colors.green),
        initialRoute: '/',
        onGenerateRoute: generateRoute,
      ),
    );
  }
}
