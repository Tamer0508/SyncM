import 'package:flutter/material.dart';
import 'dart:math';

/// Animated equalizer bars that respond to playback state
/// Shows 3 bars that animate when music is playing
class AnimatedEqualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const AnimatedEqualizer({
    Key? key,
    required this.isPlaying,
    this.color = Colors.green,
    this.size = 24,
  }) : super(key: key);

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<AnimationController> _barControllers;
  late final Random _random;

  static const int _barCount = 3;
  static const double _minBarHeight = 0.3;
  static const double _maxBarHeight = 1.0;

  @override
  void initState() {
    super.initState();
    _random = Random();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _barControllers = List.generate(
      _barCount,
      (_) => AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: 400 + _random.nextInt(200),
        ),
      ),
    );

    if (widget.isPlaying) {
      _startAnimation();
    }
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
    for (var controller in _barControllers) {
      if (!controller.isAnimating) {
        controller.forward();
      }
    }
  }

  void _stopAnimation() {
    for (var controller in _barControllers) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (var controller in _barControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _resetBarAnimation(int index) {
    _barControllers[index]
      ..reset()
      ..duration = Duration(
        milliseconds: 400 + _random.nextInt(200),
      )
      ..forward().then((_) {
        if (widget.isPlaying) {
          _resetBarAnimation(index);
        }
      });
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

    // Adjust bar spacing and sizing for small sizes
    final isSmall = widget.size <= 16;
    final barWidth = isSmall ? widget.size * 0.08 : widget.size * 0.12;
    final barSpacing = isSmall ? widget.size * 0.06 : widget.size * 0.08;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(
          _barCount,
          (index) {
            return AnimatedBuilder(
              animation: _barControllers[index],
              builder: (context, child) {
                final animation = _barControllers[index];

                // Create a wave-like effect
                late double height;
                if (animation.value < 0.5) {
                  // Going up (0 to 0.5 maps to 0.3 to 1.0)
                  height = _minBarHeight +
                      (animation.value * 2) * (_maxBarHeight - _minBarHeight);
                } else {
                  // Going down (0.5 to 1.0 maps to 1.0 to 0.3)
                  height = _maxBarHeight -
                      ((animation.value - 0.5) * 2) *
                          (_maxBarHeight - _minBarHeight);
                }

                if (widget.isPlaying && !animation.isAnimating) {
                  _resetBarAnimation(index);
                }

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: barWidth,
                        height: widget.size * height * 0.7,
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(barWidth / 2),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
