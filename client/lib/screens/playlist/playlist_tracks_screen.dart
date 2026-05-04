import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;

  const PlaylistTracksScreen({
    Key? key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
  }) : super(key: key);

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;

      final tracks = await api.getPlaylistTracks(widget.playlistId);

      if (mounted) {
        setState(() {
          _tracks = tracks;
        });
      }
    } catch (e, stack) {
      print('Error loading tracks: $e');
      print(stack);

      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: const Color(0xFF121212),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.playlistName),
              background: widget.imageUrl != null
                  ? Image.network(widget.imageUrl!, fit: BoxFit.cover)
                  : Container(color: Colors.grey),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else if (_tracks.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Нет треков',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final t = _tracks[i];

                  return ListTile(
                    leading: t['imageUrl'] != null
                        ? Image.network(t['imageUrl'], width: 50)
                        : const Icon(Icons.music_note, color: Colors.white),

                    title: Text(
                      t['name'] ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),

                    subtitle: Text(
                      t['artist'] ?? '',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
        ],
      ),
    );
  }
}