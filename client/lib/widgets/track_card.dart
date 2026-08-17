import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playback_provider.dart';
import '../theme.dart';
import 'animated_equalizer.dart';

class TrackCard extends StatefulWidget {
  const TrackCard({
    super.key,
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs,
    this.isLiked = false,
    this.isActive = false,
    this.onPlay,
    this.onLike,
    this.onMore,
    this.showLike = true,
    this.showMore = false,
    this.trailing,
    this.footer,
    this.selected = false,
  });

  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationMs;
  final bool isLiked;
  final bool isActive;
  final VoidCallback? onPlay;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final bool showLike;
  final bool showMore;
  final Widget? trailing;
  final Widget? footer;
  final bool selected;

  @override
  State<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<TrackCard> with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late final AnimationController _bounceController;
  late final Animation<double> _bounce;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _bounceController = AnimationController(vsync: this, duration: AppMotion.medium);
    _bounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(TrackCard old) {
    super.didUpdateWidget(old);
    if (old.isLiked != widget.isLiked) _isLiked = widget.isLiked;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _toggleLike() {
    setState(() => _isLiked = !_isLiked);
    widget.onLike?.call();
    _bounceController.forward(from: 0);
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final isPlaying = context.select<PlaybackProvider, bool>((pb) => pb.isPlaying);
    final highlighted = widget.selected || widget.isActive;

    final Color background;
    if (highlighted) {
      background = colors.primaryContainer;
    } else if (_pressed) {
      background = colors.surfaceContainerHigh;
    } else {
      background = Colors.transparent;
    }

    return AnimatedScale(
      scale: _pressed && !context.reduceMotion ? 0.985 : 1.0,
      duration: AppMotion.press,
      curve: AppMotion.enter,
      child: Material(
        color: background,
        animationDuration: AppMotion.press,
        borderRadius: BorderRadius.circular(AppRadius.row),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPlay,
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Artwork(url: widget.artworkUrl, colors: colors),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.isActive && isPlaying)
                              Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.xs + 2),
                                child: AnimatedEqualizer(
                                  isPlaying: true,
                                  color: highlighted
                                      ? colors.onPrimaryContainer
                                      : colors.primary,
                                  size: 14,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: texts.titleSmall?.copyWith(
                                  color: highlighted ? colors.onPrimaryContainer : null,
                                  fontWeight:
                                      widget.isActive ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.artist.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.bodySmall?.copyWith(
                              color: highlighted
                                  ? colors.onPrimaryContainer.withValues(alpha: 0.75)
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.durationMs != null && widget.durationMs! > 0) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _formatDuration(widget.durationMs!),
                      // context.timecode вместо ручной настройки цифр:
                      // длительность — это время, а у времени в приложении
                      // теперь свой голос. Табличные цифры внутри стиля, так
                      // что колонка по-прежнему не дрожит при прокрутке.
                      style: context.timecode(
                        color: highlighted
                            ? colors.onPrimaryContainer.withValues(alpha: 0.75)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.showLike) ...[
                    const SizedBox(width: AppSpacing.xs),
                    ScaleTransition(
                      scale: _bounce,
                      child: IconButton(
                        onPressed: _toggleLike,
                        visualDensity: VisualDensity.compact,
                        tooltip: _isLiked ? 'Убрать из любимых' : 'В любимые',
                        icon: Icon(
                          _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 20,
                          color: _isLiked ? colors.error : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (widget.showMore && widget.onMore != null)
                    IconButton(
                      onPressed: widget.onMore,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Ещё',
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: AppSpacing.sm),
                widget.footer!,
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.colors});

  final String? url;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;

    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, color: colors.primary, size: 20),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: AppRadius.small,
        child: url != null && url!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}