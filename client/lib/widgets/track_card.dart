import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TrackCard extends StatelessWidget {
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

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onPlay,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: artworkUrl != null && artworkUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: artworkUrl!,
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
                  child: Icon(Icons.music_note, color: theme.colorScheme.primary),
                ),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.music_note, color: theme.colorScheme.primary),
              ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (durationMs != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _formatDuration(durationMs!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
              ),
            ),
          GestureDetector(
            onTap: onLike,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: isLiked ? 1.12 : 1.0,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? theme.colorScheme.primary : theme.iconTheme.color,
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