import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../providers/playback_provider.dart';
import '../screens/player/now_playing.dart';
import '../theme.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const double _compactBreakpoint = 900;

  void _openPlayer(BuildContext context, Map<String, dynamic> track, String? imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => NowPlayingScreen(
          title: track['title'] as String?,
          artist: track['artist'] as String?,
          artworkUrl: imageUrl,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.emphasizedDecelerate,
            reverseCurve: AppMotion.emphasizedAccelerate,
          );
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
        transitionDuration: AppMotion.long,
        reverseTransitionDuration: AppMotion.medium,
      ),
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
    final isCompact = MediaQuery.sizeOf(context).width < _compactBreakpoint;
    final artSize = isCompact ? 44.0 : 52.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + 4,
        0,
        AppSpacing.sm + 4,
        AppSpacing.xs,
      ),
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 0,
        borderRadius: AppRadius.medium,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: isCompact ? 68 : 76,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _openPlayer(context, track, imageUrl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4),
                        child: Row(
                          children: [
                            _Artwork(
                              size: artSize,
                              bytes: imageBytes,
                              url: imageUrl,
                              colors: colors,
                            ),
                            const SizedBox(width: AppSpacing.sm + 4),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track['title'] as String? ?? 'Неизвестный трек',
                                    style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track['artist'] as String? ?? '',
                                    style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
                    iconSize: isCompact ? 26 : 30,
                    color: colors.onSurface,
                  ),
                  _PlayButton(isPlaying: pb.isPlaying, onPressed: pb.togglePlay, colors: colors),
                  IconButton(
                    onPressed: pb.skipNext,
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      semanticLabel: 'Следующий трек',
                    ),
                    iconSize: isCompact ? 26 : 30,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
            ),
            _MiniProgress(colors: colors),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onPressed, required this.colors});

  final bool isPlaying;
  final VoidCallback onPressed;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
      ),
      icon: AnimatedSwitcher(
        duration: AppMotion.short,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: AppMotion.spring),
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
      image = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
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
  const _MiniProgress({required this.colors});

  final ColorScheme colors;

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
        backgroundColor: colors.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
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