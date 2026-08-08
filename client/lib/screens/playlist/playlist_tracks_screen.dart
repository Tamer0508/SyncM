import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../widgets/mini_player.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_card.dart';
import '../player/now_playing.dart';

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;
  final bool isCustom;
  final bool embedded;

  const PlaylistTracksScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
    this.isCustom = false,
    this.embedded = false,
  });

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;
  String? _error;
  bool _unavailable = false;
  Map<String, bool> _likedMap = {};

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  static const _unavailableMessage =
      'Spotify не отдаёт содержимое чужих плейлистов — доступны только ваши '
      'собственные и совместные.';

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      List<dynamic>? rawTracks; // nullable

      if (widget.isCustom) {
        rawTracks = await api.getPlaylistTracksById(widget.playlistId);
        if (rawTracks == null) {
          // Доступ запрещён — показываем заглушку
          if (mounted) setState(() => _unavailable = true);
          return;
        }
      } else {
        try {
          rawTracks = await api.getPlaylistTracks(widget.playlistId);
        } catch (e) {
          if (e is ApiException) {
            if (e.statusCode == 403) {
              if (mounted) setState(() => _unavailable = true);
              return;
            }
            if (e.statusCode == 500) {
              if (mounted) setState(() => _unavailable = true);
              return;
            }
          }
          rethrow;
        }
      }

      final tracks = rawTracks; // теперь точно не null

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
      if (mounted) setState(() => _error = getUserFriendlyError(e));
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

    // Раскрывающаяся шапка с обложкой — только в отдельном экране.
    // Во встроенном режиме заголовок уже есть снаружи.
    final Widget sliverAppBar;
    if (!widget.embedded) {
      sliverAppBar = SliverAppBar.large(
        // SliverAppBar.large вместо ручной сборки: у него уже настроено
        // поведение крупного заголовка по Material 3 — размер, отступы и
        // переход к компактному виду при прокрутке.
        expandedHeight: 300,
        pinned: true,
        stretch: true,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        title: Text(
          widget.playlistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        flexibleSpace: FlexibleSpaceBar(
          stretchModes: const [StretchMode.zoomBackground],
          background: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => ColoredBox(color: theme.colorScheme.primaryContainer),
                  errorWidget: (_, _, _) => ColoredBox(color: theme.colorScheme.primaryContainer),
                )
              else
                ColoredBox(color: theme.colorScheme.primaryContainer),

              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      theme.colorScheme.surface.withValues(alpha: 0.55),
                      theme.colorScheme.surface,
                    ],
                    stops: const [0.35, 0.8, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      sliverAppBar = const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm));
    }

    final content = CustomScrollView(
      slivers: [
        sliverAppBar,
        if (_loading)
          SliverFillRemaining(
            child: const SkeletonList(itemCount: 8, avatarRadius: 24),
          )
        else if (_unavailable)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings, size: 64, color: theme.iconTheme.color?.withValues(alpha: 0.8)),
                  const SizedBox(height: 12),
                  Text(_unavailableMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75))),
                ],
              ),
            ),
          )
        else if (_error != null)
          SliverFillRemaining(
            child: Center(
              child: Text(_error!,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
            ),
          )
        else if (_unavailable)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings, size: 64, color: theme.iconTheme.color?.withValues(alpha: 0.8)),
                  const SizedBox(height: 12),
                  Text(
                    _unavailableMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_tracks.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text('Нет треков',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
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
                            // showError вместо 'Ошибка: $e': текст исключения
                            // пользователю ничего не объясняет.
                            if (mounted) showError(context, e);
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
      bottomNavigationBar: const MiniPlayerDock(),
      backgroundColor: theme.colorScheme.surface,
      body: content,
    );
  }
}