import 'package:flutter/material.dart';

import '../theme.dart';

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  String? title,
}) {
  if (context.isWideWindow) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _SheetBody(title: title, showHandle: false, child: builder(ctx)),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (ctx) => _SheetBody(title: title, child: builder(ctx)),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.child,
    this.title,
    this.showHandle = true,
  });

  final Widget child;
  final String? title;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle) ...[
              const SizedBox(height: AppSpacing.sm + 4),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ],
            if (title != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(title!, style: context.texts.titleMedium),
            ],
            SizedBox(height: title != null ? AppSpacing.sm : AppSpacing.sm + 4),
            Flexible(child: child),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class AppSheetAction extends StatelessWidget {
  const AppSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.iconColor,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = danger ? colors.error : colors.onSurface;

    return ListTile(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      leading: Icon(icon, color: iconColor ?? foreground),
      title: Text(label, style: context.texts.bodyLarge?.copyWith(color: foreground)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: context.texts.bodySmall),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      minVerticalPadding: AppSpacing.sm,
    );
  }
}