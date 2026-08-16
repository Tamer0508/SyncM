import 'package:flutter/material.dart';

import '../theme.dart';

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Skeleton old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    if (context.reduceMotion) return widget.child;

    final colors = context.colors;
    final base = colors.surfaceContainerHigh;
    final highlight = colors.surfaceContainerHighest;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final slide = _controller.value * 2 - 0.5;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, highlight, base],
                stops: [
                  (slide - 0.3).clamp(0.0, 1.0),
                  slide.clamp(0.0, 1.0),
                  (slide + 0.3).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Прямоугольник-заглушка.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.circle = false,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            circle ? null : (borderRadius ?? BorderRadius.circular(AppRadius.xs)),
      ),
    );
  }
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key, this.avatarRadius = 24});

  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          SkeletonBox(
            width: avatarRadius * 2,
            height: avatarRadius * 2,
            circle: true,
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonTrackTile extends StatelessWidget {
  const SkeletonTrackTile({
    super.key,
    this.titleWidth = 180,
    this.artistWidth = 110,
  });

  final double titleWidth;
  final double artistWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadius.medium,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48, borderRadius: AppRadius.small),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: titleWidth, height: 14),
                const SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: artistWidth, height: 11),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const SkeletonBox(width: 32, height: 11),
          const SizedBox(width: AppSpacing.md),
          const SkeletonBox(width: 20, height: 20, circle: true),
          const SizedBox(width: AppSpacing.sm + 4),
          const SkeletonBox(width: 4, height: 18),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.padding,
    this.avatarRadius = 24,
    this.itemBuilder,
    this.spacing = AppSpacing.xs,
  });

  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final double avatarRadius;
  final double spacing;

  final Widget Function(BuildContext context, int index)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < itemCount; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              itemBuilder?.call(context, i) ??
                  SkeletonListTile(avatarRadius: avatarRadius),
            ],
          ],
        ),
      ),
    );
  }
}

class SkeletonTrackList extends StatelessWidget {
  const SkeletonTrackList({super.key, this.itemCount = 8, this.padding});

  final int itemCount;
  final EdgeInsetsGeometry? padding;

  static const _titleWidths = [180.0, 132.0, 214.0, 156.0, 198.0];
  static const _artistWidths = [110.0, 84.0, 138.0, 96.0, 120.0];

  @override
  Widget build(BuildContext context) {
    return SkeletonList(
      itemCount: itemCount,
      padding: padding,
      itemBuilder: (context, i) => SkeletonTrackTile(
        titleWidth: _titleWidths[i % _titleWidths.length],
        artistWidth: _artistWidths[i % _artistWidths.length],
      ),
    );
  }
}

class SkeletonSessionCard extends StatelessWidget {
  const SkeletonSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: AppRadius.large,
        ),
        child: Column(
          children: [
            // Два круга внахлёст — тот же знак, что появится.
            const SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: 34),
                    child: SkeletonBox(width: 44, height: 44, circle: true),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 34),
                    child: SkeletonBox(width: 44, height: 44, circle: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: 168, height: 18),
            const SizedBox(height: AppSpacing.sm + 2),
            const SkeletonBox(width: 280, height: 12),
            const SizedBox(height: AppSpacing.lg),
            SkeletonBox(
              width: 176,
              height: AppSizes.buttonHeight,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonProfileHeader extends StatelessWidget {
  const SkeletonProfileHeader({super.key, this.avatarRadius = 48});

  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            SkeletonBox(
              width: avatarRadius * 2,
              height: avatarRadius * 2,
              circle: true,
            ),
            const SizedBox(width: AppSpacing.lg),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 64, height: 11),
                  SizedBox(height: AppSpacing.sm + 2),
                  SkeletonBox(width: 210, height: 28),
                  SizedBox(height: AppSpacing.sm + 2),
                  SkeletonBox(width: 148, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonSectionHeader extends StatelessWidget {
  const SkeletonSectionHeader({super.key, this.titleWidth = 156});

  final double titleWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: titleWidth, height: 20),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(width: 108, height: 11),
      ],
    );
  }
}

/// Горизонтальный ряд заглушек-карточек плейлистов.
class SkeletonPlaylistRow extends StatelessWidget {
  const SkeletonPlaylistRow({super.key, this.itemCount = 3, this.cardWidth = 150});

  final int itemCount;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm + 4),
        itemBuilder: (_, _) => SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SkeletonBox(
                  height: double.infinity,
                  borderRadius: AppRadius.medium,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const SkeletonBox(width: 100, height: 12),
              const SizedBox(height: AppSpacing.xs + 2),
              const SkeletonBox(width: 60, height: 10),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}