import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/screen_chrome.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/auth_provider.dart';
// hide Config: пакет экспортирует свой класс с таким же именем, и он
// сталкивается с нашим config.dart. Скрываем чужой, а не прячем свой за
// префиксом — Config.baseUrl используется по всему приложению без него.
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import '../../services/socket_service.dart';
import '../../theme.dart';
import 'play_history_screen.dart';
import 'blocked_users_screen.dart';
import 'legal_document_screen.dart';
import 'privacy_policy_screen.dart';
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
  const SettingsScreen({
    super.key,
    this.embedded = false,
    this.onBack,
    this.onOpenHistory,
  });

  /// Как открыть историю. На широкой раскладке её показывает главный экран.
  final VoidCallback? onOpenHistory;

  /// Как вернуться из встроенного вида.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final body = _SettingsBody(onOpenHistory: onOpenHistory);

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
  const _SettingsBody({this.onOpenHistory});

  final VoidCallback? onOpenHistory;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  bool _isUploading = false;

  /// Открытый раздел настроек.
  ///
  /// На широкой раскладке раздел показывается ВНУТРИ настроек, а не
  /// отдельным маршрутом: маршрут закрыл бы боковую панель и панель
  /// воспроизведения, как и любой полноэкранный переход на десктопе.
  String? _openSectionTitle;

  List<Widget> Function(BuildContext context)? _openSectionBuilder;

  Widget Function(BuildContext context, VoidCallback onBack)? _openChildScreen;

  void _openChild(
    BuildContext context,
    Widget Function(BuildContext context, VoidCallback onBack) builder,
  ) {
    if (context.isWideWindow) {
      setState(() => _openChildScreen = builder);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => builder(ctx, () => Navigator.of(ctx).pop()),
    ));
  }

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

    // Проверка mounted после await: пока открыт системный выбор файла,
    // экран мог быть закрыт, и обращение к context привело бы к ошибке.
    if (!mounted) return;

    // Кадрирование перед загрузкой. Аватар везде показывается кругом, поэтому
    // некруглое изображение всё равно обрезалось бы — но по центру и без
    // участия пользователя, который не понял бы, почему пропала часть кадра.
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
      // Расширение всегда png: экран кадрирования кодирует результат именно
      // в него, и прежнее имя файла (например, .jpg) ввело бы сервер в
      // заблуждение при определении типа.
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
    final isDesktop = context.isWideWindow;

    String themeName() => switch (theme.themeMode) {
          ThemeMode.light => 'Светлая',
          ThemeMode.dark => 'Тёмная',
          _ => 'Как в системе',
        };

    void openSection(String title, List<Widget> Function(BuildContext) builder) {
      if (isDesktop) {
        setState(() {
          _openSectionTitle = title;
          _openSectionBuilder = builder;
        });
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        // builder вызывается внутри — раздел перестраивается при каждом
        // изменении настроек, как и на широком экране.
        builder: (ctx) => SettingsSectionScreen(
          title: title,
          children: builder(ctx),
        ),
      ));
    }

    final childScreen = _openChildScreen;
    if (childScreen != null) {
      return childScreen(
        context,
        () => setState(() => _openChildScreen = null),
      );
    }

    if (_openSectionBuilder != null) {
      return SettingsSectionScreen(
        embedded: true,
        title: _openSectionTitle ?? 'Настройки',
        onBack: () => setState(() {
          _openSectionTitle = null;
          _openSectionBuilder = null;
        }),
        children: _openSectionBuilder!(context),
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
          onTap: () => openSection('Аккаунт', _accountSection),
        ),
        SettingsSectionTile(
          icon: Icons.palette_outlined,
          title: 'Оформление',
          summary: themeName(),
          onTap: () => openSection('Оформление', _appearanceSection),
        ),
        SettingsSectionTile(
          icon: Icons.play_circle_outline_rounded,
          title: 'Воспроизведение',
          summary: 'Задержка звука • Фоновый режим',
          onTap: () => openSection('Воспроизведение', _playbackSection),
        ),
        SettingsSectionTile(
          icon: Icons.headphones_outlined,
          title: 'Сессии',
          summary: 'Кто может звать • Приглашения',
          onTap: () => openSection('Сессии', _sessionsSection),
        ),
        SettingsSectionTile(
          icon: Icons.lock_outline_rounded,
          title: 'Приватность',
          summary: _privacySummary(user),
          onTap: () => openSection('Приватность', _privacySection),
        ),
        SettingsSectionTile(
          icon: Icons.storage_outlined,
          title: 'Данные',
          summary: 'Кэш • Удаление аккаунта',
          onTap: () => openSection('Данные', _dataSection),
        ),
        SettingsSectionTile(
          icon: Icons.info_outline_rounded,
          title: 'О приложении',
          summary: 'Версия • Приватность • Условия',
          onTap: () => openSection('О приложении', _aboutSection),
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

  String _privacySummary(User? user) {
    final hidden = [
      if (user?.isFriendsHidden == true) 'друзья',
      if (user?.isActivityHidden == true) 'активность',
      if (user?.isOnlineHidden == true) 'статус',
    ];
    if (hidden.isEmpty) return 'Ничего не скрыто';
    return 'Скрыто: ${hidden.join(', ')}';
  }

  List<Widget> _accountSection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final connected = user?.spotifyConnected == true;

    return [
      SettingsGroup(
        title: 'Профиль',
        children: [
          SettingsAction(
            icon: Icons.badge_outlined,
            title: 'Имя',
            subtitle: (user?.displayName.isNotEmpty ?? false)
                ? user!.displayName
                : 'Не задано',
            trailing: Icon(Icons.edit_outlined,
                size: 18, color: context.colors.onSurfaceVariant),
            onTap: () => _editName(context),
          ),
          if (user?.email != null && user!.email!.isNotEmpty)
            SettingsAction(
              icon: Icons.alternate_email_rounded,
              title: 'Почта',
              subtitle: user.email!,
              trailing: Icon(Icons.lock_outline_rounded,
                  size: 18, color: context.colors.onSurfaceVariant),
              onTap: _noop,
            ),
          if (user != null)
            SettingsAction(
              icon: Icons.tag_rounded,
              title: 'Идентификатор',
              subtitle: user.id,
              trailing: Icon(Icons.copy_rounded,
                  size: 18, color: context.colors.onSurfaceVariant),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: user.id));
                if (!mounted) return;
                showSuccess(context, 'Идентификатор скопирован');
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
    final appearance = context.watch<AppearanceProvider>();

    return [
      const SettingsGroup(
        title: 'Тема',
        children: [_ThemeSelectorTile()],
      ),
      SettingsGroup(
        title: 'Цвет акцента',
        children: [_AccentPicker(current: appearance.accent)],
      ),
      SettingsGroup(
        title: 'Размер текста',
        children: [_TextScaleTile(scale: appearance.textScale)],
      ),
      SettingsGroup(
        title: 'Плотность и движение',
        children: [
          SettingsSwitch(
            icon: Icons.density_medium_rounded,
            title: 'Компактный режим',
            subtitle: 'Плотнее списки — на экран помещается больше',
            value: appearance.compact,
            onChanged: appearance.setCompact,
          ),
          SettingsSwitch(
            icon: Icons.motion_photos_off_outlined,
            title: 'Меньше анимации',
            subtitle: 'Переходы без движения — если оно мешает или укачивает',
            value: appearance.reduceMotion,
            onChanged: appearance.setReduceMotion,
          ),
          SettingsSwitch(
            icon: Icons.gradient_rounded,
            title: 'Фон по обложке',
            subtitle: 'Свечение в цвет обложки на экране плеера',
            value: appearance.artworkBackground,
            onChanged: appearance.setArtworkBackground,
          ),
        ],
      ),
      SettingsGroup(
        children: [
          SettingsAction(
            icon: Icons.restart_alt_rounded,
            title: 'Сбросить оформление',
            subtitle: 'Вернуть тему, цвет, размер текста и плотность к исходным',
            onTap: () {
              context.read<AppearanceProvider>().resetAll();
              showSuccess(context, 'Оформление сброшено');
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _playbackSection(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();

    return [
      SettingsGroup(
        title: 'Синхронизация звука',
        children: [
          _AudioLatencyTile(),
          SettingsAction(
            icon: Icons.sync_rounded,
            title: 'Сверить часы с сервером',
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
            value: appearance.flag(StoreKeys.autoOpenPlayer, defaultValue: true),
            onChanged: (v) => appearance.setFlag(StoreKeys.autoOpenPlayer, v),
          ),
          SettingsSwitch(
            icon: Icons.screen_lock_portrait_rounded,
            title: 'Не гасить экран в сессии',
            subtitle: 'Пока идёт совместное прослушивание, экран остаётся включённым',
            value: appearance.flag(StoreKeys.keepScreenOn, defaultValue: true),
            onChanged: (v) => appearance.setFlag(StoreKeys.keepScreenOn, v),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Качество звука',
        children: [
          SettingsAction(
            icon: Icons.graphic_eq_rounded,
            title: 'Настройки Spotify',
            // Честная ссылка вместо переключателя.
            //
            // Качество потока, кроссфейд и нормализация громкости задаются в
            // самом Spotify: SDK ими не управляет. Переключатель здесь
            // выглядел бы рабочим, но ни на что не влиял — это хуже, чем
            // честно отправить туда, где настройка действительно есть.
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

  List<Widget> _sessionsSection(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();

    return [
      SettingsGroup(
        title: 'Приглашения',
        children: [
          SettingsSwitch(
            icon: Icons.notifications_active_outlined,
            title: 'Показывать уведомление',
            subtitle: 'Всплывающая карточка, когда друг зовёт в сессию',
            value: appearance.flag(StoreKeys.inviteNotifications, defaultValue: true),
            onChanged: (v) => appearance.setFlag(StoreKeys.inviteNotifications, v),
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
            value: appearance.flag(StoreKeys.confirmEndSession, defaultValue: true),
            onChanged: (v) => appearance.setFlag(StoreKeys.confirmEndSession, v),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Кто может звать',
        children: [
          SettingsAction(
            icon: Icons.people_outline_rounded,
            title: 'Только друзья',
            // Не переключатель: ограничение действует на сервере и изменить
            // его нельзя. Переключатель здесь выглядел бы настройкой, но
            // ничего не менял — а строка честно сообщает правило.
            subtitle: 'Пригласить в сессию может только тот, кто у вас в друзьях',
            trailing: Icon(Icons.lock_outline_rounded,
                size: 18, color: context.colors.onSurfaceVariant),
            onTap: _noop,
          ),
        ],
      ),
    ];
  }

  List<Widget> _privacySection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
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
          SettingsSwitch(
            icon: Icons.person_search_outlined,
            title: 'Скрыть из поиска',
            subtitle: 'Новые люди не найдут вас по имени. Друзья — увидят',
            value: user?.isSearchHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isSearchHidden': v}),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Чёрный список',
        children: [
          SettingsAction(
            icon: Icons.block_rounded,
            title: 'Заблокированные',
            subtitle: 'Не смогут найти вас, писать и звать в сессии',
            onTap: () => _openChild(
              context,
              (ctx, onBack) => BlockedUsersScreen(
                embedded: ctx.isWideWindow,
                onBack: onBack,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _dataSection(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();

    return [
      SettingsGroup(
        title: 'Хранилище',
        children: [
          SettingsSwitch(
            icon: Icons.bolt_outlined,
            title: 'Загружать данные при запуске',
            subtitle: 'Списки друзей и сессий готовы к моменту открытия вкладки',
            value: appearance.flag(StoreKeys.prefetchOnStart, defaultValue: true),
            onChanged: (v) => appearance.setFlag(StoreKeys.prefetchOnStart, v),
          ),
          SettingsAction(
            icon: Icons.history_rounded,
            title: 'История прослушанного',
            subtitle: 'Последние треки, которые вы включали',
            onTap: widget.onOpenHistory ??
                () => _openChild(
                      context,
                      (ctx, onBack) => PlayHistoryScreen(
                        embedded: ctx.isWideWindow,
                        onBack: onBack,
                      ),
                    ),
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
              // Оба кэша: в памяти и на диске. Первый освобождает картинки
              // прямо сейчас, второй убирает файлы, иначе они подтянутся
              // обратно при первом же показе.
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
    return [
      SettingsGroup(
        children: [
          SettingsAction(
            icon: Icons.graphic_eq_rounded,
            title: 'SyncM',
            subtitle: 'Версия ${Config.appVersion}',
            onTap: _noop,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Данные и правила',
        children: [
          SettingsAction(
            icon: Icons.shield_outlined,
            title: 'Данные и приватность',
            subtitle: 'Что приложение хранит и как это удалить',
            onTap: () => _openChild(
              context,
              (ctx, onBack) => PrivacyPolicyScreen(
                embedded: ctx.isWideWindow,
                onBack: onBack,
                onOpenFullText: () => _openChild(
                  context,
                  (innerCtx, innerBack) => LegalDocumentScreen(
                    title: 'Политика конфиденциальности',
                    assetPath: Config.privacyPolicyAsset,
                    embedded: innerCtx.isWideWindow,
                    // Возврат ведёт обратно к краткому пересказу, а не сразу
                    // в список разделов: человек пришёл оттуда.
                    onBack: () => _openChild(
                      context,
                      (c, b) => PrivacyPolicyScreen(
                        embedded: c.isWideWindow,
                        onBack: b,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SettingsAction(
            icon: Icons.gavel_rounded,
            title: 'Условия использования',
            subtitle: 'Правила пользования приложением',
            onTap: () => _openChild(
              context,
              (ctx, onBack) => LegalDocumentScreen(
                title: 'Условия использования',
                assetPath: Config.termsAsset,
                embedded: ctx.isWideWindow,
                onBack: onBack,
              ),
            ),
          ),
          SettingsAction(
            icon: Icons.description_outlined,
            title: 'Открытые лицензии',
            subtitle: 'Библиотеки, на которых работает приложение',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'SyncM',
              applicationVersion: Config.appVersion,
              applicationLegalese: 'Слушайте музыку вместе, где бы вы ни были',
            ),
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

  static void _noop() {}

  Future<void> _editName(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final current = auth.user?.displayName ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(initialName: current),
    );

    if (result == null || !mounted || result == current) return;

    try {
      await auth.updateProfile(username: result);
      if (!mounted) return;
      showSuccess(context, 'Имя обновлено');
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

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
      // Останавливаем воспроизведение до удаления: проигрыватель переживает
      // смену пользователя, и после выхода панель осталась бы играть.
      await context.read<PlaybackProvider>().stopAndClear();
      if (!mounted) return;

      final auth = context.read<AuthProvider>();
      await auth.api.deleteAccount();
      if (!mounted) return;

      // Локальное состояние чистим вручную: обычный logout обращается к
      // серверу, а пользователя там уже нет — запрос вернул бы 401.
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

    // Останавливаем воспроизведение до выхода: проигрыватель переживает
    // смену аккаунта, и без этого следующий вошедший видел бы панель с
    // чужим треком.
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

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.current});

  final AccentColor current;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          for (final accent in AccentColor.values)
            _AccentDot(
              accent: accent,
              color: accent.forBrightness(brightness),
              selected: accent == current,
              onTap: () => context.read<AppearanceProvider>().setAccent(accent),
            ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final AccentColor accent;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Название в озвучке: программам чтения с экрана цвет недоступен, и
      // без подписи все пять кружков звучали бы одинаково.
      label: accent.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: accent.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected ? context.colors.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded,
                    size: 20, color: context.roles.onMine)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Размер текста с живым примером.
class _TextScaleTile extends StatelessWidget {
  const _TextScaleTile({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Образец меняется вместе с ползунком.
          //
          // Без него выбирать приходится вслепую: число «1.15» ничего не
          // говорит о том, как это будет выглядеть в списке треков.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: AppRadius.medium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Название трека',
                  style: texts.titleSmall?.copyWith(fontSize: 14 * scale),
                ),
                const SizedBox(height: 2),
                Text(
                  'Исполнитель',
                  style: texts.bodySmall?.copyWith(
                    fontSize: 12 * scale,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.text_fields_rounded, size: 16),
              Expanded(
                child: Slider(
                  value: scale,
                  min: AppearanceProvider.minTextScale,
                  max: AppearanceProvider.maxTextScale,
                  // Шаг 5%: мельче незаметно, крупнее — скачками.
                  divisions: 9,
                  label: '${(scale * 100).round()}%',
                  onChanged: (v) =>
                      context.read<AppearanceProvider>().setTextScale(v),
                ),
              ),
              const Icon(Icons.text_fields_rounded, size: 24),
            ],
          ),
        ],
      ),
    );
  }
}
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initialName});

  final String initialName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  String? _error;

  static const int _minLength = 2;
  static const int _maxLength = 50;

  static final _allowed = RegExp(r'^[\p{L}\p{N} _\-\.]+$', unicode: true);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.addListener(_validate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _errorFor(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Введите имя';
    if (name.length < _minLength) return 'Минимум $_minLength символа';
    if (name.length > _maxLength) return 'Не более $_maxLength символов';
    if (!_allowed.hasMatch(name)) {
      return 'Только буквы, цифры, пробел и знаки . _ -';
    }
    return null;
  }

  void _validate() {
    final next = _errorFor(_controller.text);
    if (next == _error) return;
    setState(() => _error = next);
  }

  bool get _canSave => _errorFor(_controller.text) == null;

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.badge_outlined),
      title: const Text('Как вас зовут?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            maxLength: _maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: InputDecoration(
              labelText: 'Имя',
              counterText:
                  _controller.text.length > _maxLength - 15 ? null : '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Это имя видят друзья в списке, в сессиях и в приглашениях.',
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _canSave ? _submit : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}