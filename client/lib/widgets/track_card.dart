import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TrackCard extends StatefulWidget {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationMs;
  final bool isLiked;
  final void Function()? onPlay;
  final void Function()? onLike;

  const TrackCard({
    Key? key,
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs,
    this.isLiked = false,
    this.onPlay,
    this.onLike,
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
    return ListTile(
      onTap: widget.onPlay,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: widget.artworkUrl != null && widget.artworkUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: widget.artworkUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: theme.colorScheme.surfaceVariant,
                  width: 56,
                  height: 56,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: theme.colorScheme.surfaceVariant,
                  width: 56,
                  height: 56,
                  child: Icon(Icons.music_note,
                      color: theme.colorScheme.primary),
                ),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.music_note,
                    color: theme.colorScheme.primary),
              ),
      ),
      title: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        widget.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.durationMs != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _formatDuration(widget.durationMs!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
              ),
            ),
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
                  // Только затухание, без дополнительного масштаба
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  key: ValueKey(_isLiked),
                  color: _isLiked
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color,
                  size: 24,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}