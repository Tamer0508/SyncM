import 'package:flutter/material.dart';

class SessionResultsScreen extends StatelessWidget {
  const SessionResultsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Results')),
      body: const Center(child: Text('Результаты сессии')),
    );
  }
}
