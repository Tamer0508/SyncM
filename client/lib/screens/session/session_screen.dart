import 'package:flutter/material.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: const Center(child: Text('Экран совместного слушания')),
    );
  }
}
