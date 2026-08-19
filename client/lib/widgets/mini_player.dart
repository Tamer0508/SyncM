import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../providers/playback_provider.dart';
import '../screens/player/now_playing.dart';
import '../theme.dart';
import '../utils/image_cache.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
    final texts = context.texts;
    final imageBytes = pb.currentImageBytes;
    final imageUrl = track['imageUrl'] as String?;
    final isCompact = !context.isWideWindow;
    final artSize = isCompact ? 48.0 : 52.0;

    pb.ensureArtworkColor();
    final artworkColor = pb.artworkColor;
    final background = artworkColor ?? colors.surfaceContainerHigh;

    final onBackground = artworkColor != null ? Colors.white : colors.onSurface;
    final onBackgroundMuted = artworkColor != null
        ? Colors.white.withValues(alpha: 0.7)
        : colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.enter,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
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
                      onTap: () => _openPlayer(context, track, imageUrl),
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
                    colors: colors,
                    onColored: artworkColor != null,
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
            _MiniProgress(colors: colors, onColored: artworkColor != null),
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
    required this.colors,
    this.onColored = false,
  });

  final bool isPlaying;
  final VoidCallback onPressed;
  final ColorScheme colors;

  final bool onColored;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: onColored ? Colors.white : colors.primaryContainer,
        foregroundColor:
            onColored ? Colors.black : colors.onPrimaryContainer,
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
  const _MiniProgress({required this.colors, this.onColored = false});

  final ColorScheme colors;
  final bool onColored;

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
    final colors = widget.colors;
    final pb = context.read<PlaybackProvider>();
    final duration = pb.durationMs;
    final progress =
        duration <= 0 ? 0.0 : (pb.positionMs / duration).clamp(0.0, 1.0);

    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: widget.onColored
            ? Colors.white.withValues(alpha: 0.2)
            : colors.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.onColored ? Colors.white : colors.primary,
        ),
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