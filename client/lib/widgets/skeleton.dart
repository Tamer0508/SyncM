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

    final colors = context.colors;
    final base = colors.surfaceContainerHighest;
    final highlight = colors.surfaceContainerHigh;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              // Полоса света проходит слева направо. Диапазон шире границ,
              // чтобы блик успевал полностью уйти за край и не «мигал» на
              // стыке циклов.
              final slide = _controller.value * 2 - 0.5;
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
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.xs),
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
            borderRadius: BorderRadius.circular(avatarRadius),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ширины намеренно разные и не круглые: одинаковые полосы
                // выглядят как таблица, а не как имена разной длины.
                const SkeletonBox(width: 140, height: 14),
                const SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Список заглушек-строк.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.padding,
    this.avatarRadius = 24,
  });

  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < itemCount; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              SkeletonListTile(avatarRadius: avatarRadius),
            ],
          ],
        ),
      ),
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