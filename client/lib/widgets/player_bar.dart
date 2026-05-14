import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerBar extends StatelessWidget {
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final VoidCallback? onPlayPause;
  final bool isPlaying;

  const PlayerBar({Key? key, this.title = '', this.artist = '', this.thumbnailUrl, this.onPlayPause, this.isPlaying = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(color: theme.shadowColor.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4)),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPlayPause,
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(imageUrl: thumbnailUrl!, width: 52, height: 52, fit: BoxFit.cover),
                ),
              ),
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.queue_music, color: theme.colorScheme.primary),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(artist, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlayPause,
            icon: AnimatedScale(
              scale: isPlaying ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: theme.colorScheme.primary, size: 38),
            ),
          )
        ],
      ),
    );
  }
}
