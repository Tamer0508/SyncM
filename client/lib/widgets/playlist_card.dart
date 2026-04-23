import 'package:flutter/material.dart';

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(imageUrl!, width: 100, height: 100, fit: BoxFit.cover)
                  : Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white),
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