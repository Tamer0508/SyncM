import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../widgets/track_card.dart';
import '../player/now_playing.dart';

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;
  final bool isCustom;

  const PlaylistTracksScreen({
    Key? key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
    this.isCustom = false,
  }) : super(key: key);

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;
  String? _error;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      List<dynamic> tracks;

      // Проверяем, является ли плейлист пользовательским (можно передавать параметр isCustom)
      if (widget.isCustom) {
        tracks = await api.getPlaylistTracksById(widget.playlistId);
      } else {
        tracks = await api.getPlaylistTracks(widget.playlistId); // старый метод для Spotify
      }

      if (mounted) setState(() => _tracks = tracks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onTrackTap(Map<String, dynamic> track, int index) async {
  if (_isWindows) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = auth.api;
    final uri = track['uri'] as String?;

    if (uri == null || uri.isEmpty) {
      return;
    }

    final trackName = track['name'] as String? ?? '';
    final artistName = track['artist'] as String? ?? '';
      if (uri != null) {
        try {
          final api = Provider.of<AuthProvider>(context, listen: false).api;
          await api.logPlay(uri, trackName, artistName);
        } catch (_) {}
      }

    if (auth.user?.spotifyConnected != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подключите Spotify аккаунт в профиле')),
        );
      }
      return;
    }

    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    await pb.playTrack({
      'title': track['name'],
      'artist': track['artist'],
      'imageUrl': track['imageUrl'],
      'uri': uri,
      'index': index,
    }, playlistId: widget.playlistId);

    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NowPlayingScreen(
          title: track['name'] as String?,
          artist: track['artist'] as String?,
          artworkUrl: track['imageUrl'] as String?,
        ),
      ));
    }
    return;
  }

  // На мобильных — через Spotify SDK
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
                child: Text(_error!,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
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
                    final isCurrentTrack =
                        !_isWindows && pb.currentTrack?['uri'] == t['uri'];

                    final trackUri = t['uri'] as String? ?? '';

                    return StatefulBuilder(
                      builder: (context, setLocalState) {
                        bool liked =
                            false;

                        return TrackCard(
                          id: t['id'] ?? '',
                          title: t['name'] ?? '',
                          artist: t['artist'] ?? '',
                          artworkUrl: t['imageUrl'] as String?,
                          durationMs: t['durationMs'] as int?,
                          isLiked: liked,
                          onPlay: () =>
                              _onTrackTap(Map<String, dynamic>.from(t), i),
                          onLike: () async {
                            try {
                              final api = Provider.of<AuthProvider>(context,
                                      listen: false)
                                  .api;
                              final newLiked = await api.toggleLike(
                                trackUri,
                                t['name'] ?? '',
                                t['artist'] ?? '',
                              );
                              setLocalState(() => liked = newLiked);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: $e')),
                                );
                              }
                            }
                          },
                        );
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