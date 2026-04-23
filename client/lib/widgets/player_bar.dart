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
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          theme.cardColor,
          theme.cardColor.withAlpha((0.9 * 255).round()),
        ]),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // thumbnail
          if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            ClipRRect(borderRadius: BorderRadius.circular(6), child: CachedNetworkImage(imageUrl: thumbnailUrl!, width: 48, height: 48, fit: BoxFit.cover))
          else
            const Icon(Icons.queue_music, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 4),
                Text(artist, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlayPause,
            icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Theme.of(context).primaryColor, size: 36),
          )
        ],
      ),
    );
  }
}
