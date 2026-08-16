import 'package:flutter/material.dart';

import '../theme.dart';

class AnimatedNotificationButton extends StatefulWidget {
  const AnimatedNotificationButton({
    super.key,
    required this.icon,
    required this.count,
    required this.onPressed,
    this.tooltip,
    this.activeIcon,
  });

  final IconData icon;

  final IconData? activeIcon;

  final int count;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  State<AnimatedNotificationButton> createState() => _AnimatedNotificationButtonState();
}

class _AnimatedNotificationButtonState extends State<AnimatedNotificationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.long);
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _controller, curve: AppMotion.bounce));

    if (widget.count > 0) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(AnimatedNotificationButton old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasUnread = widget.count > 0;

    return IconButton(
      onPressed: widget.onPressed,
      tooltip: widget.tooltip,
      icon: ScaleTransition(
        scale: _scale,
        child: Badge.count(
          count: widget.count,
          isLabelVisible: hasUnread,
          backgroundColor: colors.error,
          textColor: colors.onError,
          child: AnimatedSwitcher(
            duration: AppMotion.short,
            child: Icon(
              hasUnread ? (widget.activeIcon ?? widget.icon) : widget.icon,
              key: ValueKey(hasUnread),
              color: hasUnread ? colors.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}