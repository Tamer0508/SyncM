import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../theme.dart';
import '../../utils/image_cache.dart';

class ArtworkSource {
  const ArtworkSource({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;

  bool get isEmpty => bytes == null && (url == null || url!.isEmpty);

  Object get identity => url ?? bytes?.length ?? 0;
}

class ArtworkPager extends StatefulWidget {
  const ArtworkPager({
    super.key,
    required this.size,
    required this.current,
    required this.previous,
    required this.next,
    required this.currentKey,
    required this.onNext,
    required this.onPrevious,
    required this.progress,
  });

  final double size;

  final ArtworkSource current;
  final ArtworkSource? previous;
  final ArtworkSource? next;

  final String currentKey;

  final VoidCallback onNext;
  final VoidCallback onPrevious;

  final ValueNotifier<double> progress;

  @override
  ArtworkPagerState createState() => ArtworkPagerState();
}
class ArtworkPagerState extends State<ArtworkPager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double _width = 1;

  int _settleTarget = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 0)
      ..addListener(() => widget.progress.value = _controller.value);
  }

  @override
  void didUpdateWidget(ArtworkPager old) {
    super.didUpdateWidget(old);

    if (widget.currentKey != old.currentKey) {
      _controller.value = 0;
      widget.progress.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _controller.value - details.delta.dx / _width;

    if (next > 0 && widget.next == null) next = 0;
    if (next < 0 && widget.previous == null) next = 0;

    _controller.value = next.clamp(-1.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final value = _controller.value;

    const distanceThreshold = 0.28;
    const velocityThreshold = 600.0;

    var target = 0;
    if (value > distanceThreshold || velocity < -velocityThreshold) {
      if (widget.next != null) target = 1;
    } else if (value < -distanceThreshold || velocity > velocityThreshold) {
      if (widget.previous != null) target = -1;
    }

    _settleTo(target, velocity: velocity);
  }

  void _settleTo(int target, {double velocity = 0}) {
    _settleTarget = target;

    if (context.reduceMotion) {
      _controller.value = target.toDouble();
      widget.progress.value = _controller.value;
      if (target == 1) {
        widget.onNext();
      } else if (target == -1) {
        widget.onPrevious();
      }
      return;
    }

    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 320, damping: 32),
      _controller.value,
      target.toDouble(),
      -velocity / _width,
    );

    _controller.animateWith(simulation).whenCompleteOrCancel(() {
      if (!mounted || _settleTarget != target) return;
      if (target == 1) {
        widget.onNext();
      } else if (target == -1) {
        widget.onPrevious();
      }
    });
  }

  bool animateTo(int direction) {
    if (direction > 0 && widget.next == null) return false;
    if (direction < 0 && widget.previous == null) return false;
    _settleTo(direction);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.previous != null)
                    _slide(-1 - t, widget.previous!),
                  _slide(-t, widget.current),
                  if (widget.next != null) _slide(1 - t, widget.next!),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Обложка, сдвинутая на [offset] ширин от центра.
  Widget _slide(double offset, ArtworkSource source) {
    return FractionalTranslation(
      translation: Offset(offset, 0),
      child: Center(
        child: _ArtworkTile(size: widget.size, source: source),
      ),
    );
  }
}

class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({required this.size, required this.source});

  final double size;
  final ArtworkSource source;

  @override
  Widget build(BuildContext context) {
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    Widget image;
    if (source.bytes != null) {
      image = Image.memory(
        source.bytes!,
        fit: BoxFit.cover,
        cacheWidth: decodeSize,
        gaplessPlayback: true,
      );
    } else if (source.url != null && source.url!.isNotEmpty) {
      image = AppNetworkImage(url: source.url!, width: size, height: size);
    } else {
      image = ColoredBox(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Icon(Icons.music_note_rounded, size: 64, color: Colors.white54),
      );
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: AppRadius.large,
        child: SizedBox(width: size, height: size, child: image),
      ),
    );
  }
}