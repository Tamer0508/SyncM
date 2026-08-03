import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class ScrollablePlaylistRow extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double scrollStep;

  const ScrollablePlaylistRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 170,
    this.scrollStep = 130,
  });

  @override
  State<ScrollablePlaylistRow> createState() => _ScrollablePlaylistRowState();
}

class _ScrollablePlaylistRowState extends State<ScrollablePlaylistRow> {
  final ScrollController _controller = ScrollController();

  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final back = pos.pixels > pos.minScrollExtent + 1;
    final forward = pos.pixels < pos.maxScrollExtent - 1;
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
  }
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
      _controller.animateTo(clamped,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final child = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      itemCount: widget.itemCount,
      physics: const ClampingScrollPhysics(),
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: widget.itemBuilder,
    );

    // Базовая обёртка с колёсиком и средней кнопкой (для всех платформ)
    final scrollableChild = Listener(
      onPointerSignal: (ps) {
        if (ps is PointerScrollEvent) {
          final dx = ps.scrollDelta.dy != 0 ? ps.scrollDelta.dy : ps.scrollDelta.dx;
          _scrollBy(dx, animate: false);
        }
      },
      onPointerDown: (ev) {
        if ((ev.buttons & kMiddleMouseButton) != 0) {
          _middleDrag = true;
          _lastPointerPos = ev.position;
        }
      },
      onPointerMove: (ev) {
        if (_middleDrag && _lastPointerPos != null) {
          final dx = ev.position.dx - _lastPointerPos!.dx;
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
      child: child,
    );

    if (isDesktop) {
      // Десктоп: показываем стрелки
      return SizedBox(
        height: widget.height,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(
            children: [
              scrollableChild,
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _canScrollBack ? (_hover ? 1.0 : 0.65) : 0.0,
                    duration: AppMotion.short,
                    child: IgnorePointer(
                      ignoring: !_canScrollBack,
                      child: _ScrollArrow(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Назад',
                        onTap: () => _scrollBy(-widget.scrollStep),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _canScrollForward ? (_hover ? 1.0 : 0.65) : 0.0,
                    duration: AppMotion.short,
                    child: IgnorePointer(
                      ignoring: !_canScrollForward,
                      child: _ScrollArrow(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Вперёд',
                        onTap: () => _scrollBy(widget.scrollStep),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return SizedBox(
        height: widget.height,
        child: scrollableChild,
      );
    }
  }
}

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(width: 40, height: 40, child: Icon(icon)),
        ),
      ),
    );
  }
}