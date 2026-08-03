import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../providers/playback_provider.dart';
import 'app_icon_button.dart';
import 'glow_background.dart';

class NowPlayingPanelCompact extends StatefulWidget {
  const NowPlayingPanelCompact({super.key});
  @override
  State<NowPlayingPanelCompact> createState() =>
      NowPlayingPanelCompactState();
}

class NowPlayingPanelCompactState extends State<NowPlayingPanelCompact> {
  double _dragValue = 0.0;
  bool _dragging = false;
  String? _lastTrackUri;
  Color? _dominantColor;
  Color? _vibrantColor;

  int _paletteRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshPaletteIfNeeded();
  }

  Color get _fallbackDominant => Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _fallbackVibrant => Theme.of(context).colorScheme.primaryContainer;

  void _refreshPaletteIfNeeded() {
    final pb = context.read<PlaybackProvider>();
    final track = pb.currentTrack;
    if (track == null) return;

    final uri = track['uri'] as String?;
    if (uri == _lastTrackUri) return;
    _lastTrackUri = uri;

    final imageUrl = track['imageUrl'] as String?;
    final cached = imageUrl != null ? pb.paletteCache[imageUrl] : null;

    if (cached != null) {
      _applyPalette(cached);
      return;
    }

    _extractPalette(pb, imageUrl);
  }

  Future<void> _extractPalette(PlaybackProvider pb, String? imageUrl) async {
    final request = ++_paletteRequest;
    final imageBytes = pb.currentImageBytes;

    final ImageProvider provider;
    if (imageBytes != null) {
      provider = MemoryImage(imageBytes);
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      provider = NetworkImage(imageUrl);
    } else {
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(64, 64),
        maximumColorCount: 8,
      );

      if (!mounted || request != _paletteRequest) return;

      if (imageUrl != null) {
        if (pb.paletteCache.length > 60) {
          pb.paletteCache.remove(pb.paletteCache.keys.first);
        }
        pb.paletteCache[imageUrl] = palette;
      }

      _applyPalette(palette);
    } catch (err) {
      debugPrint('Palette extraction failed: $err');
    }
  }

  void _applyPalette(PaletteGenerator palette) {
    if (!mounted) return;
    setState(() {
      _dominantColor = palette.dominantColor?.color;
      _vibrantColor = palette.vibrantColor?.color ?? palette.lightVibrantColor?.color;
    });
  }

  Color get _effectiveDominant => _dominantColor ?? _fallbackDominant;
  Color get _effectiveVibrant => _vibrantColor ?? _fallbackVibrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<PlaybackProvider>(builder: (_, pb, _) {
      final track = pb.currentTrack;
      if (track == null) return const SizedBox.shrink();
      final currentUri = track['uri'] as String?;
      if (currentUri != _lastTrackUri) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshPaletteIfNeeded();
        });
      }
      final title = track['title'] ?? '';
      final artist = track['artist'] ?? '';
      final imageBytes = pb.currentImageBytes;
      final imageUrl = track['imageUrl'] as String?;
      final durationMs = pb.durationMs;
      final positionMs = pb.positionMs;
      final fraction = durationMs > 0
          ? (_dragging ? _dragValue : (positionMs / durationMs).clamp(0.0, 1.0))
          : 0.0;

      final textColor = theme.colorScheme.onSurface;
      final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);
      final timeColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
      final iconColor = theme.iconTheme.color ?? theme.colorScheme.onSurface;
      final inactiveTrackColor = theme.colorScheme.onSurface.withValues(alpha: 0.24);

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                  child: GlowBackground(
                      dominantColor: _effectiveDominant,
                      vibrantColor: _effectiveVibrant)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageBytes != null
                          ? Image.memory(imageBytes,
                              width: 120, height: 120, fit: BoxFit.cover)
                          : imageUrl != null && imageUrl.isNotEmpty
                              ? Image.network(imageUrl,
                                  width: 120, height: 120, fit: BoxFit.cover)
                              : Container(
                                  width: 120,
                                  height: 120,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  child: Icon(Icons.music_note,
                                      size: 48,
                                      color: theme.colorScheme.primary)),
                    ),
                    const SizedBox(height: 12),
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(artist,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: subtitleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    _CompactProgressBar(
                        fraction: fraction,
                        onSeek: (val) {
                          setState(() {
                            _dragValue = val;
                            _dragging = true;
                          });
                        },
                        onSeekEnd: (val) {
                          setState(() => _dragging = false);
                          pb.seekTo((val * durationMs).toInt());
                        },
                        activeColor: _effectiveVibrant,
                        inactiveColor: inactiveTrackColor),
                    const SizedBox(height: 4),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatMs(positionMs),
                                  style: TextStyle(
                                      color: timeColor, fontSize: 12)),
                              Text(_formatMs(durationMs),
                                  style:
                                      TextStyle(color: timeColor, fontSize: 12))
                            ])),
                    const SizedBox(height: 12),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          AppIconButton(
                              icon: Icons.shuffle,
                              onPressed: () => pb.setShuffle(!pb.shuffleActive),
                              color: pb.shuffleActive
                                  ? _effectiveVibrant
                                  : iconColor.withValues(alpha: 0.7),
                              size: 22),
                          AppIconButton(
                              icon: Icons.skip_previous,
                              onPressed: () {
                                pb.skipPrevious();
                                setState(() => _dragValue = 0);
                              },
                              size: 28,
                              color: iconColor),
                          Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: _effectiveVibrant),
                              child: AppIconButton(
                                  icon: pb.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  onPressed: () => pb.togglePlay(),
                                  color: theme.colorScheme.onPrimary,
                                  size: 28)),
                          AppIconButton(
                              icon: Icons.skip_next,
                              onPressed: () {
                                pb.skipNext();
                                setState(() => _dragValue = 0);
                              },
                              size: 28,
                              color: iconColor),
                          AppIconButton(
                              icon: pb.repeatMode == 'track'
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              onPressed: () => pb.cycleRepeatMode(),
                              color: pb.repeatActive
                                  ? _effectiveVibrant
                                  : iconColor.withValues(alpha: 0.7),
                              size: 22),
                        ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }
}

class _CompactProgressBar extends StatelessWidget {
  final double fraction;
  final Function(double) onSeek;
  final Function(double) onSeekEnd;
  final Color activeColor;
  final Color inactiveColor;
  const _CompactProgressBar(
      {required this.fraction,
      required this.onSeek,
      required this.onSeekEnd,
      required this.activeColor,
      required this.inactiveColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          final box = context.findRenderObject() as RenderBox;
          onSeek(details.localPosition.dx.clamp(0.0, box.size.width) /
              box.size.width);
        },
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox;
          onSeek(details.localPosition.dx.clamp(0.0, box.size.width) /
              box.size.width);
        },
        onHorizontalDragEnd: (details) {
          final box = context.findRenderObject() as RenderBox;
          onSeekEnd(details.localPosition.dx.clamp(0.0, box.size.width) /
              box.size.width);
        },
        child: Container(
            height: 20,
            alignment: Alignment.centerLeft,
            child: Stack(children: [
              Container(
                  height: 4,
                  decoration: BoxDecoration(
                      color: inactiveColor,
                      borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(2)))),
            ])),
      ),
    );
  }
}