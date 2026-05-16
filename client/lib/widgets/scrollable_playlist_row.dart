import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ScrollablePlaylistRow extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double scrollStep;

  const ScrollablePlaylistRow({
    Key? key,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 170,
    this.scrollStep = 130,
  }) : super(key: key);

  @override
  State<ScrollablePlaylistRow> createState() => _ScrollablePlaylistRowState();
}

class _ScrollablePlaylistRowState extends State<ScrollablePlaylistRow> {
  final ScrollController _controller = ScrollController();
  bool _middleDrag = false;
  Offset? _lastPointerPos;
  bool _hover = false;

  void _scrollBy(double delta, {bool animate = true}) {
    if (!_controller.hasClients) return;
    final target = _controller.position.pixels + delta;
    final min = _controller.position.minScrollExtent;
    final max = _controller.position.maxScrollExtent;
    final clamped = math.max(math.min(target, max), min);
    if (animate) {
      _controller.animateTo(clamped, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _controller.jumpTo(clamped);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Stack(
          children: [
            Listener(
              onPointerSignal: (ps) {
                if (ps is PointerScrollEvent) {
                  // Treat vertical wheel as horizontal scroll for this row
                  final dx = ps.scrollDelta.dy != 0 ? ps.scrollDelta.dy : ps.scrollDelta.dx;
                  _scrollBy(dx, animate: false);
                }
              },
              onPointerDown: (ev) {
                // Start middle-button drag
                if ((ev.buttons & kMiddleMouseButton) != 0) {
                  _middleDrag = true;
                  _lastPointerPos = ev.position;
                }
              },
              onPointerMove: (ev) {
                if (_middleDrag && _lastPointerPos != null) {
                  final dx = ev.position.dx - _lastPointerPos!.dx;
                  // Dragging to right should move content left, so invert
                  _scrollBy(-dx, animate: false);
                  _lastPointerPos = ev.position;
                }
              },
              onPointerUp: (ev) {
                if ((ev.buttons & kMiddleMouseButton) == 0) {
                  _middleDrag = false;
                  _lastPointerPos = null;
                }
              },
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.itemCount,
                physics: const ClampingScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: widget.itemBuilder,
              ),
            ),
            // Left arrow
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: _hover ? 1.0 : 0.6,
                  child: Material(
                    color: Theme.of(context).cardColor.withOpacity(0.9),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _scrollBy(-widget.scrollStep),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.chevron_left),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Right arrow
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: _hover ? 1.0 : 0.6,
                  child: Material(
                    color: Theme.of(context).cardColor.withOpacity(0.9),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _scrollBy(widget.scrollStep),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
