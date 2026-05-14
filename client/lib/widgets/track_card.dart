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
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: theme.shadowColor.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      child: ListTile(
        onTap: onPlay,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: artworkUrl != null && artworkUrl!.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: artworkUrl!,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: theme.colorScheme.surfaceVariant, width: 58, height: 58),
                  errorWidget: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceVariant,
                    width: 58,
                    height: 58,
                    child: Icon(Icons.music_note, color: theme.colorScheme.primary),
                  ),
                ),
              )
            : Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.music_note, color: theme.colorScheme.primary),
              ),
        title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(
          artist,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.75)),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: onLike,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: isLiked ? 1.12 : 1.0,
              child: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? theme.colorScheme.primary : theme.iconTheme.color),
            ),
          ),
          IconButton(icon: Icon(Icons.more_vert, color: theme.iconTheme.color), onPressed: () {}),
        ]),
      ),
    );
  }
}
