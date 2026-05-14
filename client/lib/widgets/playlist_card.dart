import 'package:flutter/material.dart';
import 'interactive_card.dart';

class PlaylistCard extends StatelessWidget {
  final String name;
  final String description;
  final String? imageUrl;
  final VoidCallback? onTap;

  const PlaylistCard({
    Key? key,
    required this.name,
    required this.description,
    this.imageUrl,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InteractiveCard(
      onTap: onTap,
      borderRadius: 12,
      margin: const EdgeInsets.only(right: 8),
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 110,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(imageUrl!, width: 100, height: 100, fit: BoxFit.cover)
                  : Container(
                      width: 100,
                      height: 100,
                      color: Theme.of(context).colorScheme.surface,
                      child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurface),
                    ),
            ),
            const SizedBox(height: 4),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}