import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/playback_provider.dart';
import 'animated_equalizer.dart';

class TrackCard extends StatefulWidget {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationMs;
  final bool isLiked;
  final bool isActive;
  final void Function()? onPlay;
  final void Function()? onLike;
  final void Function()? onMore;
  final bool showLike;
  final bool showMore;
  final Widget? trailing;
  final Widget? footer;
  final bool selected;

  const TrackCard({
    Key? key,
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
    this.showMore = true,
    this.trailing,
    this.footer,
    this.selected = false,
  }) : super(key: key);

  @override
  State<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<TrackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _scaleAnimation;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(_bounceController);
  }

  @override
  void didUpdateWidget(TrackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLiked != widget.isLiked) {
      setState(() {
        _isLiked = widget.isLiked;
      });
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleLike() {
    setState(() {
      _isLiked = !_isLiked;
    });
    widget.onLike?.call();

    _bounceController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    final backgroundColor = widget.selected
        ? theme.colorScheme.primary.withOpacity(0.08)
        : Colors.transparent;

    return Material(
      color: backgroundColor,
      child: InkWell(
        onTap: widget.onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Compact thumbnail or icon (always visible)
              SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: widget.artworkUrl != null && widget.artworkUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.artworkUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.colorScheme.surfaceVariant,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceVariant,
                            child: Icon(
                              Icons.music_note,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.music_note,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title and artist with equalizer indicator
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Animated equalizer (if track is active and playing)
                        if (widget.isActive && pb.isPlaying)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: AnimatedEqualizer(
                              isPlaying: true,
                              color: theme.colorScheme.primary,
                              size: 14,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: widget.isActive
                                  ? theme.colorScheme.primary
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                    if (widget.footer != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle(
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                            ) ?? const TextStyle(fontSize: 12),
                        child: widget.footer!,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.durationMs != null) ...[
                const SizedBox(width: 10),
                Text(
                  _formatDuration(widget.durationMs!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
                  ),
                ),
              ],
              if (widget.trailing != null) ...[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
              if (widget.showLike && widget.onLike != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _handleLike,
                  child: AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) => Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(_isLiked),
                        color: _isLiked
                            ? theme.colorScheme.primary
                            : theme.iconTheme.color,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.showMore && widget.onMore != null) ...[
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    widget.onMore?.call();
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Share'),
                    ),
                    const PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Text('Add to Playlist'),
                    ),
                  ],
                  child: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: theme.iconTheme.color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}