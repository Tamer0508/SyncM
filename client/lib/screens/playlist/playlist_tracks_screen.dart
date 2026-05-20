import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../widgets/track_card.dart';
import '../player/now_playing.dart';

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
      if (mounted) setState(() => _tracks = tracks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onTrackTap(Map<String, dynamic> track, int index) async {
    final pb = Provider.of<PlaybackProvider>(context, listen: false);

    if (!pb.isConnected) {
      final connected = await pb.connect();
      if (!connected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось подключиться к Spotify')),
        );
        return;
      }
    }

    await pb.playTrack(
      {
        'title': track['name'],
        'artist': track['artist'],
        'imageUrl': track['imageUrl'],
        'uri': track['uri'],
        'index': index,
      },
      playlistId: widget.playlistId,
    );

    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NowPlayingScreen(
          title: track['name'] as String?,
          artist: track['artist'] as String?,
          artworkUrl: track['imageUrl'] as String?,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pb = Provider.of<PlaybackProvider>(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.playlistName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              background: widget.imageUrl != null
                  ? Image.network(widget.imageUrl!, fit: BoxFit.cover)
                  : Container(color: theme.colorScheme.primary.withOpacity(0.3)),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text('Нет треков',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                    )),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final t = _tracks[i];
                    final isCurrentTrack = pb.currentTrack?['uri'] == t['uri'];
                    final isPlaying = isCurrentTrack && pb.isPlaying;

                    return TrackCard(
                      id: t['id'] ?? '',
                      title: t['name'] ?? '',
                      artist: t['artist'] ?? '',
                      artworkUrl: t['imageUrl'] as String?,
                      durationMs: t['durationMs'] as int?,
                      isLiked: false, // можно расширить позже
                      onPlay: () => _onTrackTap(Map<String, dynamic>.from(t), i),
                      onLike: () {
                        // TODO: лайк трека из плейлиста
                      },
                    );
                  },
                  childCount: _tracks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}