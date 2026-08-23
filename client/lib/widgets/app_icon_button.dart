import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.size,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double? size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: onPressed != null,
      scale: AppScale.control,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: size),
        color: color,
        tooltip: (tooltip != null && tooltip!.isNotEmpty) ? tooltip : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}