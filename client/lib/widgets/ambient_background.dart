import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    this.intensity = 1.0,
    this.child,
  });

  final double intensity;

  final Widget? child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 54),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.surface),

        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: CustomPaint(
                  painter: _AmbientPainter(
                    progress: _controller.value,
                    primary: colors.primary,
                    secondary: colors.tertiary,
                    accent: colors.secondary,
                    opacity: (isDark ? 0.22 : 0.30) * widget.intensity,
                  ),
                ),
              );
            },
          ),
        ),

        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.surface.withValues(alpha: 0),
                colors.surface.withValues(alpha: isDark ? 0.55 : 0.45),
              ],
              stops: const [0.45, 1],
            ),
          ),
        ),

        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.opacity,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final Color accent;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;
    final shortest = size.shortestSide;

    _glow(
      canvas,
      center: Offset(
        size.width * (0.18 + 0.10 * math.sin(t)),
        size.height * (0.16 + 0.06 * math.cos(t * 0.8)),
      ),
      radius: shortest * 0.78,
      color: primary,
    );

    _glow(
      canvas,
      center: Offset(
        size.width * (0.86 + 0.08 * math.cos(t * 0.6)),
        size.height * (0.34 + 0.09 * math.sin(t * 0.9)),
      ),
      radius: shortest * 0.62,
      color: secondary,
    );

    _glow(
      canvas,
      center: Offset(
        size.width * (0.52 + 0.12 * math.sin(t * 0.45 + 1.2)),
        size.height * (0.88 + 0.05 * math.cos(t * 0.7)),
      ),
      radius: shortest * 0.70,
      color: accent,
    );
  }

  void _glow(Canvas canvas, {required Offset center, required double radius, required Color color}) {
    canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.primary != primary ||
      old.secondary != secondary ||
      old.accent != accent;
}