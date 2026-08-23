import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_bottom_sheet.dart';

class AppMenuEntry<T> {
  const AppMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
    this.danger = false,
    this.iconColor,
    this.separated = false,
  });

  final T value;
  final IconData icon;
  final String label;

  final bool danger;

  final Color? iconColor;

  final bool separated;
}

class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.entries,
    required this.onSelected,
    this.icon = Icons.more_vert_rounded,
    this.iconColor,
    this.tooltip,
  });

  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (!context.isWideWindow) {
      return IconButton(
        icon: Icon(icon, color: iconColor),
        tooltip: tooltip,
        onPressed: () => showAppMenuSheet<T>(
          context: context,
          entries: entries,
          onSelected: onSelected,
          title: tooltip,
        ),
      );
    }

    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: PopupMenuButton<T>(
        popUpAnimationStyle: AppMotion.menu,
        menuPadding: AppSizes.menuPadding,
        icon: Icon(icon, color: iconColor),
        tooltip: tooltip,
        onSelected: onSelected,
        itemBuilder: (context) => _popupItems(entries),
      ),
    );
  }
}

Future<void> showAppMenuSheet<T>({
  required BuildContext context,
  required List<AppMenuEntry<T>> entries,
  required ValueChanged<T> onSelected,
  String? title,
}) {
  return showAppSheet<void>(
    context: context,
    title: title,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          if (entry.separated)
            const Divider(height: AppSpacing.md, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
          AppSheetAction(
            icon: entry.icon,
            label: entry.label,
            danger: entry.danger,
            iconColor: entry.iconColor,
            onTap: () => onSelected(entry.value),
          ),
        ],
      ],
    ),
  );
}

Future<T?> showAppContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AppMenuEntry<T>> entries,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future<T?>.value();

  final theme = Theme.of(context);

  return showMenu<T>(
    context: context,
    popUpAnimationStyle: AppMotion.menu,
    menuPadding: AppSizes.menuPadding,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: _popupItems(entries),
    color: theme.popupMenuTheme.color,
  );
}

List<PopupMenuEntry<T>> _popupItems<T>(List<AppMenuEntry<T>> entries) {
  final items = <PopupMenuEntry<T>>[];
  for (final entry in entries) {
    if (entry.separated) items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem<T>(
        value: entry.value,
        padding: EdgeInsets.zero,
        child: _MenuRow(entry: entry),
      ),
    );
  }
  return items;
}

class _MenuRow<T> extends StatefulWidget {
  const _MenuRow({required this.entry});

  final AppMenuEntry<T> entry;

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends State<_MenuRow<T>> {
  bool _hovered = false;
  bool _pressed = false;

  void _set({bool? hovered, bool? pressed}) {
    if (!mounted) return;
    final nextHovered = hovered ?? _hovered;
    final nextPressed = pressed ?? _pressed;
    if (nextHovered == _hovered && nextPressed == _pressed) return;
    setState(() {
      _hovered = nextHovered;
      _pressed = nextPressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    final foreground = entry.danger ? colors.error : colors.onSurface;

    final Color background;
    if (_pressed) {
      background = colors.onSurface.withValues(alpha: 0.12);
    } else if (_hovered) {
      background = colors.onSurface.withValues(alpha: 0.07);
    } else {
      background = Colors.transparent;
    }

    return Listener(
      onPointerDown: (_) => _set(pressed: true),
      onPointerUp: (_) => _set(pressed: false),
      onPointerCancel: (_) => _set(pressed: false),
      child: MouseRegion(
        onEnter: (_) => _set(hovered: true),
        onExit: (_) => _set(hovered: false, pressed: false),
        child: AnimatedContainer(
          duration: AppMotion.press,
          curve: AppMotion.enter,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 4,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                entry.icon,
                size: 20,
                color: entry.iconColor ?? foreground,
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  entry.label,
                  style: context.texts.bodyMedium?.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
