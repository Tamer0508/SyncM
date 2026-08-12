import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Карточка плейлиста для горизонтальных подборок.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.name,
    required this.description,
    this.imageUrl,
    this.onTap,
    this.width = 150,
    this.dense = false,
  });

  final bool dense;

  final String name;
  final String description;
  final String? imageUrl;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (dense) return _buildDense(context);
    final colors = context.colors;
    final texts = context.texts;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return SizedBox(
      width: width,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.medium,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _Placeholder(colors: colors),
                        errorWidget: (_, _, _) => _Placeholder(colors: colors),
                      )
                    : _Placeholder(colors: colors),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm + 2,
                  AppSpacing.sm,
                  AppSpacing.sm + 2,
                  AppSpacing.sm + 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.titleSmall,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDense(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: ClipRRect(
                  borderRadius: AppRadius.small,
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => _Placeholder(colors: colors),
                          errorWidget: (_, _, _) => _Placeholder(colors: colors),
                        )
                      : _Placeholder(colors: colors),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.titleSmall,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.primaryContainer,
      child: Center(
        child: Icon(Icons.queue_music_rounded, size: 36, color: colors.onPrimaryContainer),
      ),
    );
  }
}