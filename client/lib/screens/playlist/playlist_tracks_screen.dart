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

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

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

  // Открывает трек на Windows через Spotify app или браузер
  Future<void> _openOnWindows(Map<String, dynamic> track) async {
    final uri = track['uri'] as String?; // spotify:track:ID
    if (uri == null) return;

    // Извлекаем track ID из URI (spotify:track:XXXXXX)
    final parts = uri.split(':');
    final trackId = parts.length >= 3 ? parts[2] : null;

    // Сначала пробуем открыть в Spotify приложении
    final spotifyUri = Uri.parse(uri);
    if (await canLaunchUrl(spotifyUri)) {
      await launchUrl(spotifyUri);
      return;
    }

    // Если Spotify не установлен — открываем в браузере
    if (trackId != null) {
      final webUrl = Uri.parse('https://open.spotify.com/track/$trackId');
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onTrackTap(Map<String, dynamic> track, int index) async {
    // На Windows — открываем через url_launcher
    if (_isWindows) {
      await _openOnWindows(track);
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
          if (_isWindows)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'На Windows треки откроются в Spotify или браузере',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
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
                    final isCurrentTrack = !_isWindows && pb.currentTrack?['uri'] == t['uri'];
                    final isPlaying = isCurrentTrack && pb.isPlaying;

                    return TrackCard(
                      id: t['id'] ?? '',
                      title: t['name'] ?? '',
                      artist: t['artist'] ?? '',
                      artworkUrl: t['imageUrl'] as String?,
                      durationMs: t['durationMs'] as int?,
                      isLiked: false,
                      onPlay: () => _onTrackTap(Map<String, dynamic>.from(t), i),
                      onLike: () {},
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