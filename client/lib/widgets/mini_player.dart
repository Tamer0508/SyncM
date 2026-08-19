import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../providers/playback_provider.dart';
import '../screens/player/now_playing.dart';
import '../theme.dart';
import '../utils/image_cache.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final Set<String> _warmed = {};

  void _warmUpcoming(List<String> urls) {
    final fresh = urls.where((url) => _warmed.add(url)).toList();
    if (fresh.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in fresh) {
        precacheImage(
          CachedNetworkImageProvider(url, cacheManager: AppImageCache.manager),
          context,
          onError: (_, _) {},
        );
      }
    });
  }

  void _openPlayer(BuildContext context, Map<String, dynamic> track, String? imageUrl) {
    if (context.isWideWindow) return;

    if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('data:')) {
      precacheImage(
              CachedNetworkImageProvider(imageUrl,
                  cacheManager: AppImageCache.manager),
              context)
          .catchError((_) {});
    }

    NowPlayingScreen.open(
      context,
      title: track['title'] as String?,
      artist: track['artist'] as String?,
      artworkUrl: imageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PlaybackProvider>();
    final track = pb.currentTrack;

    if (track == null) return const SizedBox.shrink();

    final colors = context.colors;
    final imageBytes = pb.currentImageBytes;
    final imageUrl = track['imageUrl'] as String?;
    final isCompact = !context.isWideWindow;
    final artSize = isCompact ? 48.0 : 52.0;

    pb.ensureArtworkColor();
    _warmUpcoming(pb.upcomingArtworkUrls);
    final artworkColor = pb.artworkColor;
    final background = artworkColor ?? colors.surfaceContainerHigh;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: background),
        duration: AppMotion.tint,
        curve: AppMotion.move,
        builder: (context, animated, child) {
          final bg = animated ?? background;

          final light = ThemeData.estimateBrightnessForColor(bg) == Brightness.light;
          final onBackground = light ? Colors.black : Colors.white;
          final onBackgroundMuted = onBackground.withValues(alpha: 0.7);

          return _MiniPlayerBody(
            track: track,
            imageUrl: imageUrl,
            imageBytes: imageBytes,
            isCompact: isCompact,
            artSize: artSize,
            background: bg,
            onBackground: onBackground,
            onBackgroundMuted: onBackgroundMuted,
            onOpen: () => _openPlayer(context, track, imageUrl),
          );
        },
      ),
    );
  }
}

class _MiniPlayerBody extends StatelessWidget {
  const _MiniPlayerBody({
    required this.track,
    required this.imageUrl,
    required this.imageBytes,
    required this.isCompact,
    required this.artSize,
    required this.background,
    required this.onBackground,
    required this.onBackgroundMuted,
    required this.onOpen,
  });

  final Map<String, dynamic> track;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final bool isCompact;
  final double artSize;
  final Color background;
  final Color onBackground;
  final Color onBackgroundMuted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PlaybackProvider>();
    final colors = context.colors;
    final texts = context.texts;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: isCompact ? 60 : 68,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onOpen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
                        child: Row(
                          children: [
                            _Artwork(
                              size: artSize,
                              bytes: imageBytes,
                              url: imageUrl,
                              colors: colors,
                            ),
                            const SizedBox(width: AppSpacing.sm + 2),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track['title'] as String? ?? 'Неизвестный трек',
                                    style: texts.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: onBackground,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track['artist'] as String? ?? '',
                                    style: texts.bodySmall?.copyWith(color: onBackgroundMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: pb.skipPrevious,
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      semanticLabel: 'Предыдущий трек',
                    ),
                    iconSize: isCompact ? 24 : 28,
                    color: onBackground,
                  ),
                  _PlayButton(
                    isPlaying: pb.isPlaying,
                    onPressed: pb.togglePlay,
                    // Кнопка берёт цвета от подложки: на цветной она белая с
                    // тёмной иконкой, на обычной — акцентная.
                    background: onBackground,
                    foreground: background,
                  ),
                  IconButton(
                    onPressed: pb.skipNext,
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      semanticLabel: 'Следующий трек',
                    ),
                    iconSize: isCompact ? 24 : 28,
                    color: onBackground,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
            ),
            _MiniProgress(color: onBackground),
          ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  final Color background;

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      icon: AnimatedSwitcher(
        duration: AppMotion.short,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: AppMotion.enter),
          child: child,
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(isPlaying),
          size: 26,
          semanticLabel: isPlaying ? 'Пауза' : 'Воспроизвести',
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.size,
    required this.bytes,
    required this.url,
    required this.colors,
  });

  final double size;
  final Uint8List? bytes;
  final String? url;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: colors.primaryContainer,
      child: Icon(Icons.music_note_rounded, color: colors.onPrimaryContainer, size: size * 0.5),
    );

    Widget image;
    if (bytes != null) {
      image = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty && !url!.startsWith('data:')) {
      image = AppNetworkImage(
        url: url!,
        width: size,
        height: size,
        placeholder: placeholder,
      );
    } else {
      image = placeholder;
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xs), child: image),
    );
  }
}

class _MiniProgress extends StatefulWidget {
  const _MiniProgress({required this.color});

  final Color color;

  @override
  State<_MiniProgress> createState() => _MiniProgressState();
}

class _MiniProgressState extends State<_MiniProgress> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pb = context.read<PlaybackProvider>();
    final duration = pb.durationMs;
    final progress =
        duration <= 0 ? 0.0 : (pb.positionMs / duration).clamp(0.0, 1.0);

    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: widget.color.withValues(alpha: 0.2),
        valueColor: AlwaysStoppedAnimation<Color>(widget.color),
      ),
    );
  }
}

class MiniPlayerDock extends StatelessWidget {
  const MiniPlayerDock({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      top: false,
      child: MiniPlayer(),
    );
  }
}