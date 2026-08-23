import 'package:flutter/material.dart';

import '../theme.dart';

class GlowBackground extends StatefulWidget {
  const GlowBackground({
    super.key,
    required this.dominantColor,
    required this.vibrantColor,
  });

  final Color dominantColor;
  final Color vibrantColor;

  @override
  State<GlowBackground> createState() => GlowBackgroundState();
}

class GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _dominant;
  late Animation<Color?> _vibrant;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.tint);
    _dominant = _tween(widget.dominantColor, widget.dominantColor);
    _vibrant = _tween(widget.vibrantColor, widget.vibrantColor);
    _controller.forward();
  }

  Animation<Color?> _tween(Color from, Color to) =>
      ColorTween(begin: from, end: to).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.move),
      );

  @override
  void didUpdateWidget(covariant GlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dominantColor == widget.dominantColor &&
        oldWidget.vibrantColor == widget.vibrantColor) {
      return;
    }

    _dominant = _tween(_dominant.value ?? oldWidget.dominantColor, widget.dominantColor);
    _vibrant = _tween(_vibrant.value ?? oldWidget.vibrantColor, widget.vibrantColor);

    _controller
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dominant = _dominant.value ?? widget.dominantColor;
          final vibrant = _vibrant.value ?? widget.vibrantColor;

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.2,
                colors: [
                  vibrant.withValues(alpha: 0.3),
                  dominant.withValues(alpha: 0.2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
