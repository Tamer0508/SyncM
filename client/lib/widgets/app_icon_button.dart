import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double splashRadius;
  final Color? color;
  final double? size;
  final String? tooltip;

  const AppIconButton({
    Key? key,
    required this.icon,
    this.onPressed,
    this.splashRadius = 18.0,
    this.color,
    this.size,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(splashRadius),
        splashColor: theme.colorScheme.primary.withOpacity(0.15),
        highlightColor: Colors.transparent,
        child: Tooltip(
          message: tooltip ?? '',
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              color: color ?? theme.iconTheme.color,
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}