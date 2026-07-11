import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../widgets/track_card.dart';
import '../../widgets/app_icon_button.dart';
import '../player/now_playing.dart';
import '../../utils/notifications.dart';

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;
  final bool isCustom;
  final bool embedded;

  const PlaylistTracksScreen({
    Key? key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
    this.isCustom = false,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;
  String? _error;
  Map<String, bool> _likedMap = {};

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
      if (widget.isCustom) {
        tracks = await api.getPlaylistTracksById(widget.playlistId);
      } else {
        tracks = await api.getPlaylistTracks(widget.playlistId);
      }

      final likedTracks = await api.getLikedTracks();
      final Map<String, bool> likedMap = {};
      for (var t in likedTracks) {
        likedMap[t['spotifyUri']] = true;
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _likedMap = likedMap;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onTrackTap(Map<String, dynamic> track, int index) async {
    final uri = track['uri'] as String?;
    final trackName = track['name'] as String? ?? '';
    final artistName = track['artist'] as String? ?? '';
    if (uri == null || uri.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = auth.api;
    final pb = Provider.of<PlaybackProvider>(context, listen: false);

    await api.logPlay(uri, trackName, artistName);

    if (_isWindows) {
      if (auth.user?.spotifyConnected != true) {
        if (mounted) {
          showAppNotification(context,
              message: 'Подключите Spotify аккаунт в профиле',
              type: NotificationType.error);
        }
        return;
      }

      await pb.playTrack(
        {
          'title': track['name'],
          'artist': track['artist'],
          'imageUrl': track['imageUrl'],
          'uri': uri,
          'index': index,
        },
        playlistId: widget.isCustom ? null : widget.playlistId,
      );
    } else {
      if (!pb.isConnected) {
        final connected = await pb.connect();
        if (!connected && mounted) {
          showAppNotification(context,
              message: 'Не удалось подключиться к Spotify',
              type: NotificationType.error);
          return;
        }
      }
      await pb.playTrack(
        {
          'title': track['name'],
          'artist': track['artist'],
          'imageUrl': track['imageUrl'],
          'uri': uri,
          'index': index,
        },
        playlistId: widget.isCustom ? null : widget.playlistId,
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (!isDesktop && mounted) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return NowPlayingScreen(
              title: track['name'] as String?,
              artist: track['artist'] as String?,
              artworkUrl: track['imageUrl'] as String?,
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide transition from bottom
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);

            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pb = Provider.of<PlaybackProvider>(context);

    // SliverAppBar только для режима не-embedded (мобильные устройства)
    final Widget sliverAppBar;
    if (!widget.embedded) {
      sliverAppBar = SliverAppBar(
        expandedHeight: 280,
        pinned: true,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        flexibleSpace: FlexibleSpaceBar(
          title: Text(
            widget.playlistName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black.withOpacity(0.5)),
              ],
            ),
          ),
          background: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imageUrl != null)
                Image.network(widget.imageUrl!, fit: BoxFit.cover)
              else
                Container(color: theme.colorScheme.primary.withOpacity(0.3)),
              Container(color: Colors.black.withOpacity(0.3)),
            ],
          ),
        ),
      );
    } else {
      // В десктопной версии не показываем SliverAppBar, только отступ
      sliverAppBar = const SliverToBoxAdapter(child: SizedBox(height: 8));
    }

    final content = CustomScrollView(
      slivers: [
        sliverAppBar,
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
                  final trackUri = t['uri'] as String? ?? '';
                  final isActive = pb.currentTrack?['uri'] == trackUri;
                  
                  return StatefulBuilder(
                    builder: (context, setLocalState) {
                      bool liked = _likedMap[trackUri] ?? false;
                      return TrackCard(
                        id: t['id'] ?? '',
                        title: t['name'] ?? '',
                        artist: t['artist'] ?? '',
                        artworkUrl: t['imageUrl'] as String?,
                        durationMs: t['durationMs'] as int?,
                        isLiked: liked,
                        isActive: isActive,
                        onPlay: () => _onTrackTap(Map<String, dynamic>.from(t), i),
                        onLike: () async {
                          try {
                            final api = Provider.of<AuthProvider>(context, listen: false).api;
                            final newLiked = await api.toggleLike(
                              trackUri,
                              t['name'] ?? '',
                              t['artist'] ?? '',
                            );
                            setState(() {
                              if (newLiked) {
                                _likedMap[trackUri] = true;
                              } else {
                                _likedMap.remove(trackUri);
                              }
                            });
                            setLocalState(() => liked = newLiked);
                          } catch (e) {
                            if (mounted) {
                              showAppNotification(context,
                                  message: 'Ошибка: $e',
                                  type: NotificationType.error);
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
    );

    if (widget.embedded) {
      return content; // возвращаем только список треков без Scaffold
    }
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: content,
    );
  }
}