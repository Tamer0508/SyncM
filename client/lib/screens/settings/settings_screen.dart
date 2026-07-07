import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/playback_provider.dart';
import '../../services/session_foreground_service.dart';
import '../../utils/notifications.dart';

class SettingsScreen extends StatelessWidget {
  final bool embedded;
  const SettingsScreen({Key? key, this.embedded = false}) : super(key: key);

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
    // Единый файловый пикер для всех платформ
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,            // получаем bytes сразу (работает и на мобилках)
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    // Проверка расширения
    final ext = file.extension ?? '';
    if (!['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext.toLowerCase())) {
      showAppNotification(context,
          message: 'Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
          type: NotificationType.error);
      return;
    }

    setState(() => _isUploading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      // Передаём байты и имя файла (bytes гарантированно есть, т.к. withData: true)
      await auth.uploadAvatar(file.bytes!, file.name);
      if (mounted) {
        showAppNotification(context,
            message: 'Аватарка обновлена', type: NotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context,
            message: 'Ошибка загрузки', type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final avatarUrl = user?.avatarUrl;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // Аватар и имя
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadAvatar,
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        image: avatarUrl != null && avatarUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(avatarUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: avatarUrl == null || avatarUrl.isEmpty
                            ? theme.colorScheme.primaryContainer
                            : null,
                      ),
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Center(
                              child: Icon(
                                Icons.person,
                                size: 56,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 3,
                          ),
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.displayName ?? 'Пользователь',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _NameEditor(
                currentName: user?.displayName ?? '',
                onSaved: (newName) async {
                  try {
                    await auth.updateProfile(username: newName.trim());
                  } catch (e) {
                    if (mounted) {
                      showAppNotification(context,
                          message: 'Ошибка', type: NotificationType.error);
                    }
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Тема оформления
        Text(
          'Тема',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('Системная'),
              icon: Icon(Icons.settings_brightness),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Светлая'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Тёмная'),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {themeProvider.themeMode},
          onSelectionChanged: (selected) {
            themeProvider.setThemeMode(selected.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.comfortable,
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: MaterialStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Приватность
        Text(
          'Приватность',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _PrivacySwitchTile(
          icon: Icons.people_outline,
          title: 'Скрыть количество друзей',
          subtitle: 'Никто не увидит количество ваших друзей и общих друзей',
          value: user?.isFriendsHidden ?? false,
          onChanged: (val) async {
            try {
              await auth.updateSettings({'isFriendsHidden': val});
            } catch (e) {
              showAppNotification(context,
                  message: 'Ошибка', type: NotificationType.error);
            }
          },
        ),
        const Divider(height: 1),
        _PrivacySwitchTile(
          icon: Icons.timeline,
          title: 'Скрыть активность',
          subtitle: 'Ваша активность в сессиях не будет видна другим',
          value: user?.isActivityHidden ?? false,
          onChanged: (val) async {
            try {
              await auth.updateSettings({'isActivityHidden': val});
            } catch (e) {
              showAppNotification(context,
                  message: 'Ошибка', type: NotificationType.error);
            }
          },
        ),
        const Divider(height: 1),
        _PrivacySwitchTile(
          icon: Icons.visibility_off,
          title: 'Скрыть онлайн-статус',
          subtitle: 'Друзья не увидят, когда вы в сети',
          value: user?.isOnlineHidden ?? false,
          onChanged: (val) async {
            try {
              await auth.updateSettings({'isOnlineHidden': val});
            } catch (e) {
              showAppNotification(context,
                  message: 'Ошибка', type: NotificationType.error);
            }
          },
        ),
        const SizedBox(height: 32),

        // ─── Фаза 7.3: калибровка задержки звука (Bluetooth) ────────────────
        Text(
          'Синхронизация звука',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Если в сессии звук на этом устройстве отстаёт от других '
          '(например, через Bluetooth-наушники), сдвиньте задержку вперёд, '
          'пока музыка не совпадёт.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const _AudioLatencyTile(),

        const SizedBox(height: 32),

        // ─── Шаг 2: фоновая работа сессии ───────────────────────────────────
        Text(
          'Фоновое воспроизведение',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Чтобы синхронизация не прерывалась при погашенном экране, разрешите '
          'приложению работать в фоне без ограничений батареи. На некоторых '
          'телефонах (Xiaomi, Huawei) дополнительно включите «Автозапуск» в '
          'настройках приложения.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            await SessionForegroundService.requestPermissions();
            if (context.mounted) {
              showAppNotification(context,
                  message: 'Проверьте разрешения в системном окне',
                  type: NotificationType.info);
            }
          },
          icon: const Icon(Icons.battery_saver),
          label: const Text('Разрешить работу в фоне'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final opened =
                await SessionForegroundService.openAutostartSettings();
            if (context.mounted && !opened) {
              showAppNotification(context,
                  message:
                      'Откройте настройки приложения и включите автозапуск вручную',
                  type: NotificationType.info);
            }
          },
          icon: const Icon(Icons.settings_applications_outlined),
          label: const Text('Настроить автозапуск'),
        ),
        const SizedBox(height: 8),
        Text(
          'Xiaomi/Redmi: включите «Автозапуск», а в разделе батареи выберите '
          '«Нет ограничений». Иначе система может закрыть приложение при '
          'выключенном экране.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// Плитка калибровки задержки аудиовыхода.
class _AudioLatencyTile extends StatelessWidget {
  const _AudioLatencyTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pb = Provider.of<PlaybackProvider>(context);
    final latency = pb.audioLatencyMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.headphones, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              'Задержка звука',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            Text(
              '$latency мс',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: latency.toDouble().clamp(0, 1000),
          min: 0,
          max: 1000,
          divisions: 40, // шаг 25мс
          label: '$latency мс',
          onChanged: (v) {
            pb.setAudioLatency(v.round());
          },
        ),
        if (latency > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => pb.setAudioLatency(0),
              child: const Text('Сбросить'),
            ),
          ),
      ],
    );
  }
}

class _NameEditor extends StatefulWidget {
  final String currentName;
  final Future<void> Function(String) onSaved;

  const _NameEditor(
      {Key? key, required this.currentName, required this.onSaved})
      : super(key: key);

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
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

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
        activeColor: theme.colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}