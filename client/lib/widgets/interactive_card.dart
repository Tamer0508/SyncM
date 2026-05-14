import 'package:flutter/material.dart';

class InteractiveCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;

  const InteractiveCard({
    Key? key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.color,
  }) : super(key: key);

  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<InteractiveCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeInOut,
      margin: widget.margin ?? EdgeInsets.zero,
      transform: Matrix4.identity()..scale(_pressed ? 0.995 : 1.0),
      child: Material(
        color: widget.color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.all(0),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
