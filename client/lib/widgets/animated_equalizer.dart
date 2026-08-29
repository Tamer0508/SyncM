import 'package:flutter/material.dart';
import 'dart:math';

class AnimatedEqualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    this.color = Colors.green,
    this.size = 24,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late final List<AnimationController> _barControllers;
  late final Random _random;

  static const int _barCount = 3;
  static const double _minBarHeight = 0.3;
  static const double _maxBarHeight = 1.0;

  @override
  void initState() {
    super.initState();
    _random = Random();

    _barControllers = List.generate(
      _barCount,
      (_) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + _random.nextInt(200)),
      ),
    );

    if (widget.isPlaying) _startAnimation();
  }

  @override
  void didUpdateWidget(AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _startAnimation();
      } else {
        _stopAnimation();
      }
    }
  }

  void _startAnimation() {
    for (final controller in _barControllers) {
      if (!controller.isAnimating) {
        controller.repeat(reverse: true);
      }
    }
  }

  void _stopAnimation() {
    for (final controller in _barControllers) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    for (final controller in _barControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPlaying) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Icon(
            Icons.music_note,
            color: widget.color,
            size: widget.size * 0.8,
          ),
        ),
      );
    }

    final isSmall = widget.size <= 16;
    final barWidth = isSmall ? widget.size * 0.08 : widget.size * 0.12;
    final barSpacing = isSmall ? widget.size * 0.06 : widget.size * 0.08;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (index) {
          return AnimatedBuilder(
            animation: _barControllers[index],
            builder: (context, child) {
              final height = _minBarHeight +
                  _barControllers[index].value * (_maxBarHeight - _minBarHeight);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
                child: Container(
                  width: barWidth,
                  height: widget.size * height * 0.7,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}