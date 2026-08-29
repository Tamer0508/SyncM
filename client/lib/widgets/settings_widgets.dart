import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/appearance_provider.dart';
import '../theme.dart';
import 'pressable.dart';
import 'screen_chrome.dart';

class SettingsMetrics {
  const SettingsMetrics._();

  static const double pagePadding = AppSpacing.md;

  static const double contentMaxWidth = 720;

  static const double rowMinHeight = 56;

  static const double iconColumn = 24;

  static const double iconSize = 22;

  static const double iconGap = AppSpacing.md;

  static const double rowPaddingH = AppSpacing.md;
  static const double rowPaddingV = 12;

  static const double dividerIndent = rowPaddingH + iconColumn + iconGap;

  static const double sectionPadding = AppSpacing.sm + 4;

  static const double sectionIconBox = 40;

  static const double sectionDividerIndent =
      sectionPadding + sectionIconBox + AppSpacing.md;

  static const double groupGap = AppSpacing.lg;
}

enum SettingsTone {
  normal,

  danger,
}

class SettingsScrollView extends StatelessWidget {
  const SettingsScrollView({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final free = constraints.maxWidth - SettingsMetrics.contentMaxWidth;
        final side = free <= 0
            ? SettingsMetrics.pagePadding
            : SettingsMetrics.pagePadding + free / 2;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.sm,
            side,
            AppSpacing.xl,
          ),
          children: children,
        );
      },
    );
  }
}

class SettingsSectionScreen extends StatelessWidget {
  const SettingsSectionScreen({
    super.key,
    required this.title,
    required this.children,
    this.embedded = false,
    this.onBack,
  });

  final String title;
  final List<Widget> children;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      embedded: embedded,
      contentMaxWidth: SettingsMetrics.contentMaxWidth,
      header: ScreenHeader(
        title: title,
        onBack: onBack ?? (embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: SettingsScrollView(children: children),
    );
  }
}

class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel({
    super.key,
    required this.text,
    this.tone = SettingsTone.normal,
  });

  final String text;
  final SettingsTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == SettingsTone.danger
        ? context.colors.error
        : context.colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: context.texts.labelLarge?.copyWith(
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        SettingsMetrics.groupGap,
      ),
      child: Text(
        text,
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    required this.children,
    this.footer,
    this.tone = SettingsTone.normal,
    this.dividerIndent = SettingsMetrics.dividerIndent,
  });

  final String? title;
  final List<Widget> children;

  final String? footer;

  final SettingsTone tone;

  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: dividerIndent,
          color: colors.outlineVariant.withValues(alpha: 0.6),
        ));
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: footer == null ? SettingsMetrics.groupGap : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) SettingsGroupLabel(text: title!, tone: tone),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: AppRadius.large,
              border: tone == SettingsTone.danger
                  ? Border.all(color: colors.error.withValues(alpha: 0.35))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
          if (footer != null) SettingsNote(footer!),
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.tone = SettingsTone.normal,
    this.enabled = true,
    this.semanticsToggled,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;

  final String? value;

  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsTone tone;
  final bool enabled;

  final bool? semanticsToggled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final danger = tone == SettingsTone.danger;
    final base = danger ? colors.error : colors.onSurface;

    final titleColor = enabled ? base : base.withValues(alpha: 0.38);
    final mutedColor = enabled
        ? colors.onSurfaceVariant
        : colors.onSurfaceVariant.withValues(alpha: 0.38);
    final iconColor = danger ? titleColor : mutedColor;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SettingsMetrics.rowPaddingH,
        vertical: SettingsMetrics.rowPaddingV,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            SizedBox(
              width: SettingsMetrics.iconColumn,
              child: Icon(
                icon,
                size: SettingsMetrics.iconSize,
                color: iconColor,
              ),
            ),
            const SizedBox(width: SettingsMetrics.iconGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: texts.bodyLarge?.copyWith(
                    color: titleColor,
                    height: 1.25,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: texts.bodySmall?.copyWith(color: mutedColor),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: texts.bodyMedium?.copyWith(color: mutedColor),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            IconTheme.merge(
              data: IconThemeData(size: 20, color: mutedColor),
              child: trailing!,
            ),
          ],
        ],
      ),
    );

    final body = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SettingsMetrics.rowMinHeight,
      ),
      child: content,
    );

    if (onTap == null || !enabled) {
      return Semantics(
        enabled: enabled,
        toggled: semanticsToggled,
        child: body,
      );
    }

    return Semantics(
      button: true,
      toggled: semanticsToggled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.onSurface.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return context.roles.mine.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return colors.onSurface.withValues(alpha: 0.045);
            }
            return null;
          }),
          child: body,
        ),
      ),
    );
  }
}

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.trailing,
    this.value,
    this.danger = false,
    this.enabled = true,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  final String? value;

  final Widget? trailing;
  final VoidCallback onTap;

  final bool danger;
  final bool enabled;

  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      trailing: trailing ??
          (chevron ? const Icon(Icons.chevron_right_rounded) : null),
      tone: danger ? SettingsTone.danger : SettingsTone.normal,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class SettingsInfo extends StatelessWidget {
  const SettingsInfo({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.value,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      trailing: trailing,
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        semanticsToggled: value,
        onTap: enabled ? () => onChanged(!value) : null,
        trailing: ExcludeSemantics(
          child: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

class SettingsFlagSwitch extends StatelessWidget {
  const SettingsFlagSwitch({
    super.key,
    required this.flagKey,
    required this.title,
    this.subtitle,
    this.icon,
    this.defaultValue = false,
  });

  final String flagKey;

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool defaultValue;

  @override
  Widget build(BuildContext context) {
    final appearance = context.read<AppearanceProvider>();

    return ValueListenableBuilder<bool>(
      valueListenable: appearance.flagListenable(
        flagKey,
        defaultValue: defaultValue,
      ),
      builder: (context, value, _) => SettingsSwitch(
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: (next) => appearance.setFlag(flagKey, next),
      ),
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.child,
    this.icon,
    this.title,
    this.description,
    this.trailing,
  });

  final Widget child;
  final IconData? icon;
  final String? title;
  final String? description;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final hasHead = title != null || description != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SettingsMetrics.rowPaddingH,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHead) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  SizedBox(
                    width: SettingsMetrics.iconColumn,
                    child: Icon(
                      icon,
                      size: SettingsMetrics.iconSize,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: SettingsMetrics.iconGap),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: texts.bodyLarge?.copyWith(height: 1.25),
                        ),
                      if (description != null) ...[
                        if (title != null) const SizedBox(height: 3),
                        Text(
                          description!,
                          style: texts.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

class SettingsSectionTile extends StatelessWidget {
  const SettingsSectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;

  final String summary;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Pressable(
      scale: AppScale.row,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.onSurface.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return context.roles.mine.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return colors.onSurface.withValues(alpha: 0.045);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SettingsMetrics.sectionPadding,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: SettingsMetrics.sectionIconBox,
                  height: SettingsMetrics.sectionIconBox,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: AppRadius.medium,
                  ),
                  child: Icon(icon, size: 21, color: colors.onSurface),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: texts.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: texts.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
