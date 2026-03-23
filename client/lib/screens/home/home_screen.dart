import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/track_card.dart';
import '../../providers/session_provider.dart';
import '../../providers/playback_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  

  @override
  void initState() {
    super.initState();
    // could load featured playlists or sessions
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your Playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    PlaylistCard(name: 'Favorites', description: 'Your liked songs'),
                    PlaylistCard(name: 'Party', description: 'Party mix'),
                    PlaylistCard(name: 'Chill', description: 'Relaxing tunes'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton(
                      onPressed: () async {
                        await Provider.of<SessionProvider>(context, listen: false).fetchMySessions();
                      },
                      child: const Text('Refresh'))
                ],
              ),
              const SizedBox(height: 8),
              Consumer<SessionProvider>(builder: (_, prov, __) {
                if (prov.loading) return const Center(child: CircularProgressIndicator());
                if (prov.sessions.isEmpty) return const Center(child: Text('No active sessions'));
                return Column(
                  children: prov.sessions
                      .map((s) => ListTile(
                            title: Text(s.name),
                            subtitle: Text('Host: ${s.id.substring(0, 6)}'),
                            onTap: () => Navigator.of(context).pushNamed('/session'),
                          ))
                      .toList(),
                );
              }),
              const SizedBox(height: 16),
              const Text('Suggested Tracks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Column(children: [
                GestureDetector(
                  onTap: () {
                    final track = {'id': 't1', 'title': 'Song A', 'artist': 'Artist 1', 'artworkUrl': ''};
                    Provider.of<PlaybackProvider>(context, listen: false).playTrack(track);
                    Navigator.of(context).pushNamed('/player', arguments: track);
                  },
                  child: TrackCard(
                    id: 't1',
                    title: 'Song A',
                    artist: 'Artist 1',
                    artworkUrl: '',
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    final track = {'id': 't2', 'title': 'Song B', 'artist': 'Artist 2', 'artworkUrl': ''};
                    Provider.of<PlaybackProvider>(context, listen: false).playTrack(track);
                    Navigator.of(context).pushNamed('/player', arguments: track);
                  },
                  child: TrackCard(
                    id: 't2',
                    title: 'Song B',
                    artist: 'Artist 2',
                    artworkUrl: '',
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    final track = {'id': 't3', 'title': 'Song C', 'artist': 'Artist 3', 'artworkUrl': ''};
                    Provider.of<PlaybackProvider>(context, listen: false).playTrack(track);
                    Navigator.of(context).pushNamed('/player', arguments: track);
                  },
                  child: TrackCard(
                    id: 't3',
                    title: 'Song C',
                    artist: 'Artist 3',
                    artworkUrl: '',
                  ),
                ),
              ])
            ],
          ),
        ),
      ),
    );
  }
}

