import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/session_foreground_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/tappable_avatar.dart';
import 'avatar_crop_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final body = _SettingsBody();

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: body,
    );
  }
}

class _SettingsBody extends StatefulWidget {
  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  bool _isUploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // получаем bytes сразу (работает и на мобильных)
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    const allowed = ['png', 'jpg', 'jpeg', 'gif', 'webp'];
    final ext = (file.extension ?? '').toLowerCase();
    if (!allowed.contains(ext)) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
        type: NotificationType.error,
      );
      return;
    }

    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Не удалось прочитать файл',
        type: NotificationType.error,
      );
      return;
    }

    if (!mounted) return;

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(imageBytes: bytes),
        fullscreenDialog: true,
      ),
    );

    if (cropped == null) return; // пользователь отказался
    if (!mounted) return;

    setState(() => _isUploading = true);
    try {
      final auth = context.read<AuthProvider>();
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      await auth.uploadAvatar(cropped, fileName);
      if (!mounted) return;
      showAppNotification(
        context,
        message: 'Аватарка обновлена',
        type: NotificationType.success,
      );
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _AvatarBlock(
          avatarUrl: user?.effectiveAvatarUrl,
          displayName: user?.displayName ?? 'Пользователь',
          isUploading: _isUploading,
          onEdit: _isUploading ? null : _pickAndUploadAvatar,
        ),
        const SizedBox(height: AppSpacing.md),
        _NameEditor(
          currentName: user?.displayName ?? '',
          onSaved: (newName) async {
            try {
              await auth.updateProfile(username: newName.trim());
              if (!mounted) return;
              showSuccess(context, 'Имя обновлено');
            } catch (err) {
              if (!mounted) return;
              showError(context, err);
            }
          },
        ),

        const _SettingsSection(
          title: 'Оформление',
          child: _ThemeSelector(),
        ),

        _SettingsSection(
          title: 'Приватность',
          child: _SettingsCard(
            children: [
              _PrivacySwitchTile(
                icon: Icons.people_outline_rounded,
                title: 'Скрыть количество друзей',
                subtitle: 'Никто не увидит количество ваших друзей и общих друзей',
                value: user?.isFriendsHidden ?? false,
                onChanged: (val) => _updatePrivacy({'isFriendsHidden': val}),
              ),
              const Divider(height: 1, indent: 56),
              _PrivacySwitchTile(
                icon: Icons.timeline_rounded,
                title: 'Скрыть активность',
                subtitle: 'Ваша активность в сессиях не будет видна другим',
                value: user?.isActivityHidden ?? false,
                onChanged: (val) => _updatePrivacy({'isActivityHidden': val}),
              ),
              const Divider(height: 1, indent: 56),
              _PrivacySwitchTile(
                icon: Icons.visibility_off_rounded,
                title: 'Скрыть онлайн-статус',
                subtitle: 'Друзья не увидят, когда вы в сети',
                value: user?.isOnlineHidden ?? false,
                onChanged: (val) => _updatePrivacy({'isOnlineHidden': val}),
              ),
            ],
          ),
        ),

        const _SettingsSection(
          title: 'Синхронизация звука',
          description:
              'Если в сессии звук на этом устройстве отстаёт от других '
              '(например, через Bluetooth-наушники), сдвиньте задержку вперёд, '
              'пока музыка не совпадёт.',
          child: _SettingsCard(children: [_AudioLatencyTile()]),
        ),

        _SettingsSection(
          title: 'Фоновое воспроизведение',
          description:
              'Чтобы синхронизация не прерывалась при погашенном экране, '
              'разрешите приложению работать в фоне без ограничений батареи.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: _requestBackgroundPermissions,
                icon: const Icon(Icons.battery_saver_rounded),
                label: const Text('Разрешить работу в фоне'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _openAutostartSettings,
                icon: const Icon(Icons.settings_applications_outlined),
                label: const Text('Настроить автозапуск'),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              _Hint(
                'На Xiaomi и Redmi включите «Автозапуск», а в разделе батареи '
                'выберите «Нет ограничений» — иначе система закроет приложение '
                'при выключенном экране.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updatePrivacy(Map<String, bool> patch) async {
    try {
      await context.read<AuthProvider>().updateSettings(patch);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  Future<void> _requestBackgroundPermissions() async {
    await SessionForegroundService.requestPermissions();
    if (!mounted) return;
    showAppNotification(
      context,
      message: 'Проверьте разрешения в системном окне',
      type: NotificationType.info,
    );
  }

  Future<void> _openAutostartSettings() async {
    final opened = await SessionForegroundService.openAutostartSettings();
    if (!mounted || opened) return;
    showAppNotification(
      context,
      message: 'Откройте настройки приложения и включите автозапуск вручную',
      type: NotificationType.info,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    this.description,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.texts.titleLarge),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _Hint(description!),
          ],
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(children: children),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.avatarUrl,
    required this.displayName,
    required this.isUploading,
    required this.onEdit,
  });

  final String? avatarUrl;
  final String displayName;
  final bool isUploading;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Stack(
          children: [
            TappableAvatar(
              imageUrl: avatarUrl,
              radius: 60,
              showRing: true,
              title: displayName,
              heroTag: 'settings-avatar',
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Material(
                color: colors.primary,
                shape: CircleBorder(
                  side: BorderSide(color: colors.surface, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onEdit,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: isUploading
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.onPrimary,
                            ),
                          )
                        : Icon(Icons.photo_camera_rounded, color: colors.onPrimary, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(displayName, style: context.texts.headlineSmall),
      ],
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('Система'),
          icon: Icon(Icons.settings_brightness_rounded),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Светлая'),
          icon: Icon(Icons.light_mode_rounded),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Тёмная'),
          icon: Icon(Icons.dark_mode_rounded),
        ),
      ],
      selected: {themeProvider.themeMode},
      onSelectionChanged: (selected) => themeProvider.setThemeMode(selected.first),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        visualDensity: VisualDensity.comfortable,
      ),
    );
  }
}

class _AudioLatencyTile extends StatelessWidget {
  const _AudioLatencyTile();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final pb = context.watch<PlaybackProvider>();
    final latency = pb.audioLatencyMs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.headphones_rounded, color: colors.primary),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Text('Задержка звука', style: texts.bodyLarge),
              ),
              Text(
                '$latency мс',
                style: texts.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: latency.toDouble().clamp(0, 1000),
            max: 1000,
            divisions: 40, // шаг 25 мс
            label: '$latency мс',
            onChanged: (v) => pb.setAudioLatency(v.round()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: latency > 0 ? () => pb.setAudioLatency(0) : null,
              child: const Text('Сбросить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameEditor extends StatefulWidget {
  final String currentName;
  final Future<void> Function(String) onSaved;

  const _NameEditor(
      {required this.currentName, required this.onSaved});

  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
  late TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _controller.text.trim();
    if (newName.isEmpty || newName == widget.currentName) {
      setState(() => _editing = false);
      return;
    }
    if (newName.length < 2) {
      showAppNotification(context,
          message: 'Имя должно содержать минимум 2 символа',
          type: NotificationType.error);
      return;
    }
    if (newName.length > 50) {
      showAppNotification(context,
          message: 'Имя должно содержать не более 50 символов',
          type: NotificationType.error);
      return;
    }
    if (RegExp(r'^\s+$').hasMatch(newName)) {
      showAppNotification(context,
          message: 'Имя не может состоять только из пробелов',
          type: NotificationType.error);
      return;
    }
    if (!RegExp(r'^[\p{L}\p{N} _\-\.]+$', unicode: true).hasMatch(newName)) {
      showAppNotification(context,
          message: 'Имя содержит недопустимые символы',
          type: NotificationType.error);
      return;
    }

    await widget.onSaved(newName);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _editing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 50,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    style: theme.textTheme.bodyLarge,
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: _save,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () {
                    _controller.text = widget.currentName;
                    setState(() => _editing = false);
                  },
                ),
              ],
            )
          : InkWell(
              onTap: () => setState(() => _editing = true),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Редактировать имя',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PrivacySwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacySwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        secondary: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
        activeThumbColor: theme.colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}