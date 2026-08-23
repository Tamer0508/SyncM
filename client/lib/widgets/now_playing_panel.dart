import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../providers/playback_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../utils/duration_text.dart';
import '../utils/image_cache.dart';
import 'app_icon_button.dart';
import 'glow_background.dart';

class NowPlayingPanelCompact extends StatefulWidget {
  const NowPlayingPanelCompact({super.key});

  @override
  State<NowPlayingPanelCompact> createState() => NowPlayingPanelCompactState();
}

class NowPlayingPanelCompactState extends State<NowPlayingPanelCompact> {
  int? _seekPreviewMs;

  String? _lastTrackUri;
  Color? _dominantColor;
  Color? _vibrantColor;

  int _paletteRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshPaletteIfNeeded();
  }

  Color get _effectiveDominant =>
      _dominantColor ?? context.colors.surfaceContainerHigh;

  Color get _effectiveVibrant => _vibrantColor ?? context.colors.primary;

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

    final palette = await pb.paletteFor(
      imageUrl: imageUrl,
      imageBytes: pb.currentImageBytes,
      fallbackKey: _lastTrackUri,
    );

    if (palette == null || !mounted || request != _paletteRequest) return;

    _applyPalette(palette);
  }

  void _applyPalette(PaletteGenerator palette) {
    if (!mounted) return;
    setState(() {
      _dominantColor = palette.dominantColor?.color;
      _vibrantColor =
          palette.vibrantColor?.color ?? palette.lightVibrantColor?.color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaybackProvider>(builder: (_, pb, _) {
      final track = pb.currentTrack;
      if (track == null) return const SizedBox.shrink();

      final currentUri = track['uri'] as String?;
      if (currentUri != _lastTrackUri) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshPaletteIfNeeded();
        });
      }

      final colors = context.colors;
      final texts = context.texts;

      final title = track['title'] as String? ?? L.of(context).playerUnknownTrack;
      final artist = track['artist'] as String? ?? '';
      final imageBytes = pb.currentImageBytes;
      final imageUrl = track['imageUrl'] as String?;
      final durationMs = pb.durationMs;

      return LayoutBuilder(builder: (context, constraints) {
        // Бюджет под обложку: ширина за вычетом отступов панели, высота — за
        // вычетом того, что стоит ниже (подписи, полоса, таймкоды, контролы).
        const belowArtwork = 232.0;
        final widthBudget = constraints.maxWidth - AppSpacing.md * 2;
        final heightBudget = constraints.hasBoundedHeight
            ? constraints.maxHeight - belowArtwork
            : widthBudget;
        final artSize =
            (widthBudget < heightBudget ? widthBudget : heightBudget)
                .clamp(88.0, 320.0);

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: AppRadius.large,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GlowBackground(
                  dominantColor: _effectiveDominant,
                  vibrantColor: _effectiveVibrant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Artwork(
                        size: artSize,
                        bytes: imageBytes,
                        url: imageUrl,
                        colors: colors,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        title,
                        style: texts.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (artist.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          artist,
                          style: texts.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),

                      ValueListenableBuilder<int>(
                        valueListenable: pb.positionNotifier,
                        builder: (context, positionMs, _) {
                          return _PanelProgressBar(
                            positionMs: _seekPreviewMs ?? positionMs,
                            durationMs: durationMs,
                            accentColor: _effectiveVibrant,
                            onSeekStart: () =>
                                setState(() => _seekPreviewMs = positionMs),
                            onSeekChanged: (value) =>
                                setState(() => _seekPreviewMs = value),
                            onSeekEnd: (value) {
                              setState(() => _seekPreviewMs = null);
                              pb.seekTo(value);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PanelControls(
                        pb: pb,
                        accentColor: _effectiveVibrant,
                        onSeekReset: () =>
                            setState(() => _seekPreviewMs = null),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      });
    });
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
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: colors.onPrimaryContainer,
      ),
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
      child: ClipRRect(borderRadius: AppRadius.medium, child: image),
    );
  }
}

class _PanelProgressBar extends StatelessWidget {
  const _PanelProgressBar({
    required this.positionMs,
    required this.durationMs,
    required this.accentColor,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final int positionMs;
  final int durationMs;
  final Color accentColor;
  final VoidCallback onSeekStart;
  final ValueChanged<int> onSeekChanged;
  final ValueChanged<int> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final safeDuration = durationMs > 0 ? durationMs : 1;
    final value = positionMs.clamp(0, safeDuration).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: colors.onSurface.withValues(alpha: 0.24),
            thumbColor: colors.onSurface,
            overlayColor: accentColor.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            max: safeDuration.toDouble(),
            onChangeStart: (_) => onSeekStart(),
            onChanged: (v) => onSeekChanged(v.round()),
            onChangeEnd: (v) => onSeekEnd(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(positionMs), style: context.timecode()),
              Text(formatDuration(durationMs), style: context.timecode()),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelControls extends StatelessWidget {
  const _PanelControls({
    required this.pb,
    required this.accentColor,
    required this.onSeekReset,
  });

  final PlaybackProvider pb;
  final Color accentColor;
  final VoidCallback onSeekReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = colors.onSurfaceVariant;

    final onAccent =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1A1A);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        AppIconButton(
          icon: Icons.shuffle_rounded,
          size: 22,
          color: pb.shuffleActive ? accentColor : muted,
          tooltip: pb.shuffleActive ? L.of(context).playerShuffleOn : L.of(context).playerShuffle,
          onPressed: () => pb.setShuffle(!pb.shuffleActive),
        ),
        AppIconButton(
          icon: Icons.skip_previous_rounded,
          size: 28,
          color: colors.onSurface,
          tooltip: L.of(context).playerPrevious,
          onPressed: () {
            pb.goToPrevious();
            onSeekReset();
          },
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
          child: AppIconButton(
            icon: pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 28,
            color: onAccent,
            tooltip: pb.isPlaying ? L.of(context).playerPause : L.of(context).playerPlay,
            onPressed: pb.togglePlay,
          ),
        ),
        AppIconButton(
          icon: Icons.skip_next_rounded,
          size: 28,
          color: colors.onSurface,
          tooltip: L.of(context).playerNext,
          onPressed: () {
            pb.goToNext();
            onSeekReset();
          },
        ),
        AppIconButton(
          icon: pb.repeatMode == 'track'
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          size: 22,
          color: pb.repeatActive ? accentColor : muted,
          tooltip: switch (pb.repeatMode) {
            'track' => L.of(context).playerRepeatOne,
            'context' => L.of(context).playerRepeatAll,
            _ => L.of(context).playerRepeatOff,
          },
          onPressed: pb.cycleRepeatMode,
        ),
      ],
    );
  }
}
