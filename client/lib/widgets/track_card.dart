import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TrackCard extends StatelessWidget {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final bool isLiked;
  final void Function()? onPlay;
  final void Function()? onLike;

  const TrackCard({Key? key, required this.id, required this.title, required this.artist, this.artworkUrl, this.isLiked = false, this.onPlay, this.onLike}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onPlay,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: artworkUrl != null && artworkUrl!.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: artworkUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[700], width: 56, height: 56),
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[700], width: 56, height: 56, child: const Icon(Icons.music_note, color: Colors.white)),
                ),
              )
            : Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.music_note, color: Colors.white)),
        title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(
          artist,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color == null
                ? null
                : theme.textTheme.bodySmall!.color!.withAlpha((0.8 * 255).round()),
          ),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Theme.of(context).primaryColor : theme.iconTheme.color),
            onPressed: onLike,
          ),
          IconButton(icon: Icon(Icons.more_vert, color: theme.iconTheme.color), onPressed: () {}),
        ]),
      ),
    );
  }
}
