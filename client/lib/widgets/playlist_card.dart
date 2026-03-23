import 'package:flutter/material.dart';

class PlaylistCard extends StatelessWidget {
  final String name;
  final String description;

  const PlaylistCard({Key? key, required this.name, required this.description}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text(description),
      ),
    );
  }
}
