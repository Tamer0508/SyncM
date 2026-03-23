import 'package:flutter/material.dart';

class PlaylistCard extends StatelessWidget {
  final String name;
  final String description;

  const PlaylistCard({Key? key, required this.name, required this.description}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 10),
            Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color == null
                    ? null
                    : theme.textTheme.bodySmall!.color!.withAlpha((0.8 * 255).round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
