import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/screen_chrome.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import '../../services/socket_service.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../../utils/local_store.dart';
import '../../config.dart';
import '../../models/user.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/session_foreground_service.dart';
import '../../services/spotify_link_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/tappable_avatar.dart';
import 'avatar_crop_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false, this.onBack});

  /// Как вернуться из встроенного вида.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final body = _SettingsBody();

    return ScreenChrome(
      embedded: embedded,
      header: ScreenHeader(
        title: 'Настройки',
        onBack: onBack ?? (embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: body,
    );
  }
}

class _SettingsBody extends StatefulWidget {
  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  bool _isUploading = false;

  String? _openSectionTitle;
  List<Widget>? _openSectionChildren;

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
    final theme = context.watch<ThemeProvider>();
    final user = auth.user;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    String themeName() => switch (theme.themeMode) {
          ThemeMode.light => 'Светлая',
          ThemeMode.dark => 'Тёмная',
          _ => 'Как в системе',
        };

    void openSection(String title, List<Widget> children) {
      if (isDesktop) {
        setState(() {
          _openSectionTitle = title;
          _openSectionChildren = children;
        });
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettingsSectionScreen(title: title, children: children),
      ));
    }

    if (_openSectionChildren != null) {
      return SettingsSectionScreen(
        embedded: true,
        title: _openSectionTitle ?? 'Настройки',
        onBack: () => setState(() {
          _openSectionTitle = null;
          _openSectionChildren = null;
        }),
        children: _openSectionChildren!,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
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
        const SizedBox(height: AppSpacing.lg),

        SettingsSectionTile(
          icon: Icons.person_outline_rounded,
          title: 'Аккаунт',
          summary: '${user?.displayName ?? 'Имя'} • '
              '${user?.spotifyConnected == true ? 'Spotify подключён' : 'Spotify не подключён'}',
          onTap: () => openSection('Аккаунт', _accountSection(context, auth)),
        ),
        SettingsSectionTile(
          icon: Icons.palette_outlined,
          title: 'Оформление',
          summary: themeName(),
          onTap: () => openSection('Оформление', _appearanceSection(context)),
        ),
        SettingsSectionTile(
          icon: Icons.play_circle_outline_rounded,
          title: 'Воспроизведение',
          summary: 'Задержка звука • Фоновый режим',
          onTap: () => openSection('Воспроизведение', _playbackSection(context)),
        ),
        SettingsSectionTile(
          icon: Icons.headphones_outlined,
          title: 'Сессии',
          summary: 'Кто может звать • Приглашения',
          onTap: () => openSection('Сессии', _sessionsSection(context, auth)),
        ),
        SettingsSectionTile(
          icon: Icons.lock_outline_rounded,
          title: 'Приватность',
          summary: _privacySummary(user),
          onTap: () => openSection('Приватность', _privacySection(context, auth)),
        ),
        SettingsSectionTile(
          icon: Icons.storage_outlined,
          title: 'Данные',
          summary: 'Кэш • Удаление аккаунта',
          onTap: () => openSection('Данные', _dataSection(context)),
        ),
        SettingsSectionTile(
          icon: Icons.info_outline_rounded,
          title: 'О приложении',
          summary: 'Версия • Соединение',
          onTap: () => openSection('О приложении', _aboutSection(context)),
        ),

        const SizedBox(height: AppSpacing.lg),
        Center(
          child: OutlinedButton(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
              side: BorderSide(color: context.colors.error.withValues(alpha: 0.4)),
              minimumSize: const Size(200, 48),
            ),
            child: const Text('Выйти'),
          ),
        ),
      ],
    );
  }

  /// Краткая сводка приватности для подписи раздела.
  String _privacySummary(User? user) {
    final hidden = [
      if (user?.isFriendsHidden == true) 'друзья',
      if (user?.isActivityHidden == true) 'активность',
      if (user?.isOnlineHidden == true) 'статус',
    ];
    if (hidden.isEmpty) return 'Ничего не скрыто';
    return 'Скрыто: ${hidden.join(', ')}';
  }


  List<Widget> _accountSection(BuildContext context, AuthProvider auth) {
    final connected = auth.user?.spotifyConnected == true;
    return [
      SettingsGroup(
        children: [
          _NameEditor(
            currentName: auth.user?.displayName ?? '',
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
        ],
      ),
      SettingsGroup(
        title: 'Подключённые сервисы',
        children: [
          SettingsAction(
            icon: Icons.music_note_rounded,
            title: 'Spotify',
            subtitle: connected ? 'Подключён' : 'Не подключён',
            trailing: Text(
              connected ? 'Отключить' : 'Подключить',
              style: context.texts.labelMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            onTap: () =>
                connected ? disconnectSpotify(context) : connectSpotify(context),
          ),
        ],
      ),
    ];
  }

  List<Widget> _appearanceSection(BuildContext context) {
    return const [
      SettingsGroup(
        title: 'Тема',
        children: [_ThemeSelectorTile()],
      ),
    ];
  }

  List<Widget> _playbackSection(BuildContext context) {
    return [
      const SettingsGroup(
        title: 'Синхронизация звука',
        children: [_AudioLatencyTile()],
      ),
      SettingsGroup(
        title: 'Фоновый режим',
        children: [
          SettingsAction(
            icon: Icons.battery_saver_rounded,
            title: 'Разрешить работу в фоне',
            subtitle: 'Чтобы синхронизация не прерывалась при погашенном экране',
            onTap: _requestBackgroundPermissions,
          ),
          SettingsAction(
            icon: Icons.settings_applications_outlined,
            title: 'Настроить автозапуск',
            subtitle: 'На Xiaomi и Redmi без этого система закрывает приложение',
            onTap: _openAutostartSettings,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Поведение плеера',
        children: [
          SettingsSwitch(
            icon: Icons.open_in_full_rounded,
            title: 'Открывать плеер при запуске',
            subtitle: 'Полноэкранный плеер появится сразу после нажатия на трек',
            value: LocalStore.readBool(StoreKeys.autoOpenPlayer, defaultValue: true),
            onChanged: (v) => _setFlag(StoreKeys.autoOpenPlayer, v),
          ),
          SettingsSwitch(
            icon: Icons.screen_lock_portrait_rounded,
            title: 'Не гасить экран в сессии',
            subtitle: 'Пока идёт совместное прослушивание, экран остаётся включённым',
            value: LocalStore.readBool(StoreKeys.keepScreenOn, defaultValue: true),
            onChanged: (v) => _setFlag(StoreKeys.keepScreenOn, v),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Качество звука',
        children: [
          SettingsAction(
            icon: Icons.graphic_eq_rounded,
            title: 'Настройки Spotify',
            subtitle: 'Качество, кроссфейд и громкость задаются в приложении Spotify',
            onTap: () => showAppNotification(
              context,
              message: 'Откройте Spotify → Настройки → Качество звука',
              type: NotificationType.info,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _sessionsSection(BuildContext context, AuthProvider auth) {
    return [
      SettingsGroup(
        title: 'Приглашения',
        children: [
          SettingsSwitch(
            icon: Icons.notifications_active_outlined,
            title: 'Показывать уведомление',
            subtitle: 'Всплывающая карточка, когда друг зовёт в сессию',
            value: LocalStore.readBool(StoreKeys.inviteNotifications, defaultValue: true),
            onChanged: (v) => _setFlag(StoreKeys.inviteNotifications, v),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Завершение',
        children: [
          SettingsSwitch(
            icon: Icons.help_outline_rounded,
            title: 'Спрашивать перед завершением',
            subtitle: 'Подтверждение, чтобы не закрыть сессию случайно',
            value: LocalStore.readBool(StoreKeys.confirmEndSession, defaultValue: true),
            onChanged: (v) => _setFlag(StoreKeys.confirmEndSession, v),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Кто может звать',
        children: [
          SettingsAction(
            icon: Icons.people_outline_rounded,
            title: 'Только друзья',
            subtitle: 'Пригласить в сессию может только тот, кто у вас в друзьях',
            trailing: Icon(Icons.lock_outline_rounded,
                size: 18, color: context.colors.onSurfaceVariant),
            onTap: _noop,
          ),
        ],
      ),
    ];
  }

  List<Widget> _privacySection(BuildContext context, AuthProvider auth) {
    final user = auth.user;
    return [
      SettingsGroup(
        children: [
          SettingsSwitch(
            icon: Icons.people_outline_rounded,
            title: 'Скрыть количество друзей',
            subtitle: 'Никто не увидит количество ваших друзей и общих друзей',
            value: user?.isFriendsHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isFriendsHidden': v}),
          ),
          SettingsSwitch(
            icon: Icons.timeline_rounded,
            title: 'Скрыть активность',
            subtitle: 'Ваша активность в сессиях не будет видна другим',
            value: user?.isActivityHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isActivityHidden': v}),
          ),
          SettingsSwitch(
            icon: Icons.visibility_off_rounded,
            title: 'Скрыть онлайн-статус',
            subtitle: 'Друзья не увидят, когда вы в сети',
            value: user?.isOnlineHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isOnlineHidden': v}),
          ),
        ],
      ),
    ];
  }

  List<Widget> _dataSection(BuildContext context) {
    return [
      SettingsGroup(
        title: 'Хранилище',
        children: [
          SettingsSwitch(
            icon: Icons.bolt_outlined,
            title: 'Загружать данные при запуске',
            subtitle: 'Списки друзей и сессий готовы к моменту открытия вкладки',
            value: LocalStore.readBool(StoreKeys.prefetchOnStart, defaultValue: true),
            onChanged: (v) => _setFlag(StoreKeys.prefetchOnStart, v),
          ),
          SettingsAction(
            icon: Icons.cleaning_services_outlined,
            title: 'Очистить кэш',
            subtitle: 'Сохранённые списки друзей и сессий',
            onTap: () async {
              await LocalStore.clearAll();
              if (!mounted) return;
              showSuccess(context, 'Кэш очищен');
            },
          ),
          SettingsAction(
            icon: Icons.image_not_supported_outlined,
            title: 'Очистить кэш изображений',
            subtitle: 'Аватары и обложки будут загружены заново',
            onTap: () async {
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              await DefaultCacheManager().emptyCache();
              if (!mounted) return;
              showSuccess(context, 'Кэш изображений очищен');
            },
          ),
        ],
      ),
      SettingsGroup(
        title: 'Аккаунт',
        children: [
          SettingsAction(
            icon: Icons.delete_outline_rounded,
            title: 'Удалить аккаунт',
            subtitle: 'Безвозвратно удалит профиль, друзей и историю сессий',
            danger: true,
            onTap: () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    ];
  }

  List<Widget> _aboutSection(BuildContext context) {
    final connected = context.read<AuthProvider>().user != null;

    return [
      SettingsGroup(
        children: [
          const SettingsAction(
            icon: Icons.graphic_eq_rounded,
            title: 'SyncM',
            subtitle: 'Слушайте музыку вместе, где бы вы ни были',
            onTap: _noop,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Соединение',
        children: [
          SettingsAction(
            icon: Icons.cloud_outlined,
            title: 'Сервер',
            subtitle: Config.baseUrl,
            trailing: Icon(
              connected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 18,
              color: connected ? context.roles.online : context.colors.error,
            ),
            onTap: _noop,
          ),
          SettingsAction(
            icon: Icons.sync_rounded,
            title: 'Синхронизация часов',
            subtitle: _clockSyncSummary(),
            onTap: () {
              SocketService().resyncNow();
              showAppNotification(
                context,
                message: 'Часы синхронизируются заново',
                type: NotificationType.info,
              );
            },
          ),
        ],
      ),
    ];
  }

  String _clockSyncSummary() {
    final socket = SocketService();
    final offset = socket.masterOffsetMs;
    if (offset == 0) return 'Ещё не измерено — нажмите, чтобы обновить';
    final sign = offset > 0 ? '+' : '';
    return 'Расхождение с сервером: $sign$offset мс';
  }

  Future<void> _setFlag(String key, bool value) async {
    await LocalStore.saveBool(key, value);
    if (mounted) setState(() {});
  }

  static void _noop() {}

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: ctx.colors.error),
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Профиль, друзья и история сессий будут удалены безвозвратно. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<PlaybackProvider>().stopAndClear();
      if (!mounted) return;

      final auth = context.read<AuthProvider>();
      await auth.api.deleteAccount();
      if (!mounted) return;

      await auth.forgetLocalSession();
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: ctx.colors.error),
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Придётся войти заново, чтобы вернуться.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await context.read<PlaybackProvider>().stopAndClear();
    if (!mounted) return;

    await context.read<AuthProvider>().logout();
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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
            // Нажатие на сам аватар разворачивает его на весь экран, а
            // изменить фотографию можно кнопкой в углу. Раньше нажатие в
            // любое место сразу открывало выбор файла, и посмотреть свою
            // аватарку целиком было невозможно.
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

class _ThemeSelectorTile extends StatelessWidget {
  const _ThemeSelectorTile();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SegmentedButton<ThemeMode>(
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
        selected: {theme.themeMode},
        onSelectionChanged: (selected) => theme.setThemeMode(selected.first),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          visualDensity: VisualDensity.comfortable,
        ),
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

    // Собственные отступы обязательны: плитка лежит внутри карточки со
    // скруглёнными углами и обрезкой содержимого. Без них иконка упиралась в
    // край и срезалась закруглением — раньше плитка стояла прямо на фоне
    // экрана и жила на отступах списка.
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
          // Кнопка сброса всегда занимает своё место, просто становится
          // неактивной: иначе при первом же движении ползунка она появлялась
          // и сдвигала содержимое карточки вниз.
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