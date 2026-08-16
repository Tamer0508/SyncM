import 'package:flutter/material.dart';

import '../theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;

  final String title;

  final String message;

  final String? actionLabel;
  final VoidCallback? onAction;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final hasAction = actionLabel != null && onAction != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 56,
                height: compact ? 48 : 56,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: AppRadius.medium,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: compact ? 24 : 28,
                  color: colors.onSurfaceVariant,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              Text(title, style: texts.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (hasAction) ...[
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}