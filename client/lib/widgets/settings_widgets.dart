import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../providers/appearance_provider.dart';
import '../theme.dart';
import 'screen_chrome.dart';

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
      header: ScreenHeader(
        title: title,
        onBack: onBack ?? (embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: children,
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

  /// Одна-две ключевые настройки раздела через разделитель.
  final String summary;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: colors.onSurface),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: texts.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Группа строк внутри раздела.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                title!,
                style: context.texts.labelLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppRadius.large,
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// Строка с переключателем.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        secondary: icon == null ? null : Icon(icon),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
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

  /// Ключ флага в [StoreKeys].
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

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onTap;

  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? context.colors.error : null;

    return ListTile(
      onTap: onTap,
      leading: icon == null ? null : Icon(icon, color: color),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
    );
  }
}