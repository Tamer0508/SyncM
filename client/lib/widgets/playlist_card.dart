import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlaylistCard extends StatefulWidget {
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
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: _pressed ? 0.97 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 12, bottom: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (theme.brightness == Brightness.dark
                        ? Colors.black
                        : Colors.grey.withOpacity(0.2))
                    .withOpacity(_pressed ? 0.1 : 0.25),
                blurRadius: _pressed ? 4 : 8,
                offset: Offset(0, _pressed ? 1 : 4),
              ),
            ],
          ),
          child: SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Обложка
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: widget.imageUrl!,
                          height: 100,   // было 120 → уменьшено
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildPlaceholder(theme),
                          errorWidget: (_, __, ___) => _buildPlaceholder(theme),
                        )
                      : _buildPlaceholder(theme),
                ),
                // Текстовая часть
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8), // уменьшены отступы
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,   // чуть уменьшен
                        ),
                      ),
                      if (widget.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.15),
            theme.colorScheme.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: 36,
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}