import 'package:flutter/material.dart';

class TrackCard extends StatelessWidget {
  final String title;
  final String artist;

  const TrackCard({Key? key, required this.title, required this.artist}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(artist),
      leading: const Icon(Icons.music_note),
    );
  }
}
