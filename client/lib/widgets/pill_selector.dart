import 'package:flutter/material.dart';

import '../theme.dart';

class PillSelector extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            _Pill(
              label: labels[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final background = widget.selected
        ? colors.onSurface
        : (_pressed ? colors.surfaceContainerHighest : colors.surfaceContainerHigh);
    final foreground = widget.selected ? colors.surface : colors.onSurface;

    return AnimatedScale(
      scale: _pressed && !context.reduceMotion ? 0.96 : 1.0,
      duration: AppMotion.press,
      curve: AppMotion.enter,
      child: Material(
        color: background,
        animationDuration: AppMotion.press,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md + 2,
              vertical: AppSpacing.sm + 2,
            ),
            child: Text(
              widget.label,
              style: context.texts.labelLarge?.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}