import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/track_card.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({Key? key}) : super(key: key);

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  List<Map<String, dynamic>> _tracks = [];

  @override
  void initState() {
    super.initState();
    // In a real app we'd load session tracks from provider/api
  }

  void _rate(String trackId, int rating) async {
    try {
      await Provider.of<SessionProvider>(context, listen: false).rateTrack(trackId, rating);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _tracks.length,
              itemBuilder: (_, i) {
                final t = _tracks[i];
                return TrackCard(
                  id: t['id'] ?? 'unknown',
                  title: t['trackName'] ?? t['name'] ?? 'Track',
                  artist: t['artistName'] ?? t['artist'] ?? 'Artist',
                  isLiked: (t['liked'] ?? false) as bool,
                  onLike: () => _rate(t['id'] ?? '', 1),
                );
              },
            ),
          ),
          // PlayerBar could be here
        ],
      ),
    );
  }
}

