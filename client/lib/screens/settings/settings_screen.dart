import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import '../../widgets/pill_selector.dart';
import '../../widgets/screen_chrome.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
// hide Config: пакет экспортирует свой класс с таким же именем, и он
// сталкивается с нашим config.dart. Скрываем чужой, а не прячем свой за
// префиксом — Config.baseUrl используется по всему приложению без него.
import '../../services/socket_service.dart';
import '../../theme.dart';
import 'play_history_screen.dart';
import 'blocked_users_screen.dart';
import 'devices_screen.dart';
import 'legal_document_screen.dart';
import 'privacy_policy_screen.dart';
import '../../widgets/settings_widgets.dart';
import '../../utils/cache_size.dart';
import '../../utils/image_cache.dart';
import '../../utils/local_store.dart';
import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../providers/playback_provider.dart';
import '../../providers/playlists_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/session_foreground_service.dart';
import '../../services/spotify_link_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/file_save.dart';
import '../../utils/notifications.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pressable.dart';
import '../../widgets/sync_mark.dart';
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
      contentMaxWidth: SettingsMetrics.contentMaxWidth,
      header: ScreenHeader(
        title: L.of(context).settingsTitle,
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
        message: L.of(context).avatarBadFormat,
        type: NotificationType.error,
      );
      return;
    }

    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      showAppNotification(
        context,
        message: L.of(context).avatarReadFailed,
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
        message: L.of(context).avatarUpdated,
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
          ThemeMode.light => L.of(context).themeLight,
          ThemeMode.dark => L.of(context).themeDark,
          _ => L.of(context).themeSystem,
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
      return _swap(
        context,
        const ValueKey('child'),
        childScreen(context, () => setState(() => _openChildScreen = null)),
      );
    }

    if (_openSectionBuilder != null) {
      final title = _openSectionTitle ?? L.of(context).settingsTitle;
      return _swap(
        context,
        ValueKey('section:$title'),
        SettingsSectionScreen(
          embedded: true,
          title: title,
          onBack: () => setState(() {
            _openSectionTitle = null;
            _openSectionBuilder = null;
          }),
          children: _openSectionBuilder!(context),
        ),
      );
    }

    return _swap(
      context,
      const ValueKey('root'),
      SettingsScrollView(
        children: [
          _ProfileCard(
            avatarUrl: user?.effectiveAvatarUrl,
            displayName: user?.displayName ?? L.of(context).commonUser,
            spotifyConnected: user?.spotifyConnected == true,
            isUploading: _isUploading,
            onEdit: _isUploading ? null : _pickAndUploadAvatar,
          ),
          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: L.of(context).settingsGroupProfile,
            dividerIndent: SettingsMetrics.sectionDividerIndent,
            children: [
              SettingsSectionTile(
                icon: Icons.person_outline_rounded,
                title: L.of(context).sectionAccount,
                summary: user?.spotifyConnected == true
                    ? L.of(context).spotifyConnectedShort
                    : L.of(context).spotifyNotConnectedShort,
                onTap: () =>
                    openSection(L.of(context).sectionAccount, _accountSection),
              ),
              SettingsSectionTile(
                icon: Icons.shield_outlined,
                title: L.of(context).sectionSecurity,
                summary: L.of(context).summarySecurity,
                onTap: () =>
                    openSection(L.of(context).sectionSecurity, _securitySection),
              ),
            ],
          ),

          SettingsGroup(
            title: L.of(context).settingsGroupApp,
            dividerIndent: SettingsMetrics.sectionDividerIndent,
            children: [
              SettingsSectionTile(
                icon: Icons.palette_outlined,
                title: L.of(context).sectionAppearance,
                summary: themeName(),
                onTap: () => openSection(
                    L.of(context).sectionAppearance, _appearanceSection),
              ),
              SettingsSectionTile(
                icon: Icons.play_circle_outline_rounded,
                title: L.of(context).sectionPlayback,
                summary: L.of(context).summaryPlayback,
                onTap: () =>
                    openSection(L.of(context).sectionPlayback, _playbackSection),
              ),
              SettingsSectionTile(
                icon: Icons.headphones_outlined,
                title: L.of(context).sectionSessions,
                summary: L.of(context).summarySessions,
                onTap: () =>
                    openSection(L.of(context).sectionSessions, _sessionsSection),
              ),
              SettingsSectionTile(
                icon: Icons.notifications_none_rounded,
                title: L.of(context).sectionNotifications,
                summary: _notificationsSummary(context),
                onTap: () => openSection(
                    L.of(context).sectionNotifications, _notificationsSection),
              ),
            ],
          ),

          SettingsGroup(
            title: L.of(context).settingsGroupData,
            dividerIndent: SettingsMetrics.sectionDividerIndent,
            children: [
              SettingsSectionTile(
                icon: Icons.lock_outline_rounded,
                title: L.of(context).sectionPrivacy,
                summary: _privacySummary(user),
                onTap: () =>
                    openSection(L.of(context).sectionPrivacy, _privacySection),
              ),
              SettingsSectionTile(
                icon: Icons.storage_outlined,
                title: L.of(context).sectionData,
                summary: L.of(context).summaryData,
                onTap: () =>
                    openSection(L.of(context).sectionData, _dataSection),
              ),
            ],
          ),

          SettingsGroup(
            dividerIndent: SettingsMetrics.sectionDividerIndent,
            children: [
              SettingsSectionTile(
                icon: Icons.info_outline_rounded,
                title: L.of(context).sectionAbout,
                summary: L.of(context).summaryAbout,
                onTap: () =>
                    openSection(L.of(context).sectionAbout, _aboutSection),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(
                  color: context.colors.error.withValues(alpha: 0.4),
                ),
                minimumSize: const Size(200, AppSizes.buttonHeight),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(L.of(context).commonSignOut),
            ),
          ),
        ],
      ),
    );
  }

  /// Смена содержимого настроек на широкой раскладке.
  ///
  /// Разделы там открываются внутри экрана, а не отдельным маршрутом, —
  /// значит, штатного перехода между страницами нет, и раздел появлялся
  /// рывком. Короткое проявление с едва заметным сдвигом даёт то же
  /// ощущение направления, что и push на телефоне.
  Widget _swap(BuildContext context, Key key, Widget child) {
    final keyed = KeyedSubtree(key: key, child: child);
    if (!context.isWideWindow || context.reduceMotion) return keyed;

    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: keyed,
    );
  }

  String _privacySummary(User? user) {
    switch (_currentPreset(user)) {
      case 'open':
        return L.of(context).privacyPresetOpenSummary;
      case 'friends':
        return L.of(context).privacyPresetFriendsSummary;
      case 'hidden':
        return L.of(context).privacyPresetHiddenSummary;
    }

    final hidden = [
      if (user?.isSearchHidden == true) L.of(context).privacyBitSearch,
      if (user?.isOnlineHidden == true) L.of(context).privacyBitStatus,
      if (user?.isActivityHidden == true) L.of(context).privacyBitActivity,
      if (user?.isFriendsHidden == true) L.of(context).privacyBitFriends,
    ];
    if (hidden.isEmpty) return L.of(context).privacyNothingHidden;
    return L.of(context).hiddenList(hidden.join(', '));
  }

  List<Widget> _accountSection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final connected = user?.spotifyConnected == true;

    return [
      SettingsGroup(
        title: L.of(context).accountProfile,
        children: [
          SettingsAction(
            icon: Icons.badge_outlined,
            title: L.of(context).commonName,
            subtitle: (user?.displayName.isNotEmpty ?? false)
                ? user!.displayName
                : L.of(context).accountNameUnset,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editName(context),
          ),
          if (user?.email != null && user!.email!.isNotEmpty)
            SettingsInfo(
              icon: Icons.alternate_email_rounded,
              title: L.of(context).accountEmail,
              subtitle: user.email!,
              trailing: const Icon(Icons.lock_outline_rounded),
            ),
          if (user?.publicId != null)
            SettingsAction(
              icon: Icons.tag_rounded,
              title: L.of(context).accountPublicId,
              subtitle: _formatPublicId(user!.publicId!),
              trailing: const Icon(Icons.copy_rounded),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: user.publicId!));
                if (!mounted) return;
                showSuccess(context, L.of(context).accountPublicIdCopied);
              },
            ),
        ],
      ),
      SettingsGroup(
        title: L.of(context).accountConnectedServices,
        children: [_SpotifyTile(fallbackConnected: connected)],
      ),
    ];
  }

  List<Widget> _appearanceSection(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();

    // Плитки здесь сами носят заголовок с иконкой — ровно как строки, — и
    // подпись над карточкой только повторяла бы его.
    return [
      SettingsGroup(
        children: const [_ThemeModePicker(), _AccentPicker()],
      ),
      SettingsGroup(
        children: [
          _TextScaleTile(scale: appearance.textScale),
          const _LanguageTile(),
          SettingsPanel(
            icon: Icons.first_page_rounded,
            title: L.of(context).appearanceStartTab,
            description: L.of(context).appearanceStartTabHint,
            child: PillSelector(
              padding: EdgeInsets.zero,
              labels: [
                L.of(context).tabNow,
                L.of(context).tabMusic,
                L.of(context).commonFriends,
              ],
              selectedIndex: appearance.startTab,
              onSelected: context.read<AppearanceProvider>().setStartTab,
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: L.of(context).appearanceDensityGroup,
        children: [
          SettingsSwitch(
            icon: Icons.density_medium_rounded,
            title: L.of(context).appearanceCompact,
            subtitle: L.of(context).appearanceCompactHint,
            value: appearance.compact,
            onChanged: appearance.setCompact,
          ),
          SettingsSwitch(
            icon: Icons.motion_photos_off_outlined,
            title: L.of(context).appearanceReduceMotion,
            subtitle: L.of(context).appearanceReduceMotionHint,
            value: appearance.reduceMotion,
            onChanged: appearance.setReduceMotion,
          ),
          SettingsSwitch(
            icon: Icons.gradient_rounded,
            title: L.of(context).appearanceArtworkBackground,
            subtitle: L.of(context).appearanceArtworkBackgroundHint,
            value: appearance.artworkBackground,
            onChanged: appearance.setArtworkBackground,
          ),
        ],
      ),
      SettingsGroup(
        children: [
          SettingsAction(
            icon: Icons.restart_alt_rounded,
            title: L.of(context).appearanceReset,
            subtitle: L.of(context).appearanceResetHint,
            onTap: () {
              context.read<AppearanceProvider>().resetAll();
              showSuccess(context, L.of(context).appearanceResetDone);
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _playbackSection(BuildContext context) {
    final pb = context.watch<PlaybackProvider>();
    final socket = SocketService();

    return [
      SettingsGroup(
        title: L.of(context).playbackConnections,
        children: [
          // Подключено — сообщение, не кнопка: нажимать не на что, и подсветка
          // при наведении обещала бы действие, которого нет.
          if (pb.isConnected)
            SettingsInfo(
              icon: Icons.check_circle_outline_rounded,
              title: L.of(context).playbackSpotifyDevice,
              subtitle: L.of(context).playbackSpotifyConnected,
              trailing: _StatusDot(color: context.roles.spotify),
            )
          else
            SettingsAction(
              icon: Icons.error_outline_rounded,
              title: L.of(context).playbackSpotifyDevice,
              subtitle: L.of(context).playbackSpotifyDisconnected,
              trailing: const Icon(Icons.refresh_rounded),
              onTap: () async {
                final ok = await pb.connect();
                if (!mounted) return;
                if (ok) {
                  showSuccess(context, L.of(context).spotifyConnectedShort);
                } else {
                  showError(
                    context,
                    L.of(context).playbackSpotifyConnectFailed,
                    force: true,
                  );
                }
              },
            ),
          SettingsInfo(
            icon: socket.isConnected
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            title: L.of(context).playbackServerLink,
            subtitle: socket.isConnected
                ? L.of(context).playbackServerOnline
                : L.of(context).playbackServerOffline,
            trailing: _StatusDot(
              color: socket.isConnected
                  ? context.roles.online
                  : context.colors.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).playbackSyncGroup,
        children: [
          const _AudioLatencyTile(),
          SettingsAction(
            icon: Icons.sync_rounded,
            title: L.of(context).playbackClockSync,
            subtitle: _clockSyncSummary(),
            onTap: () {
              SocketService().resyncNow();
              showAppNotification(
                context,
                message: L.of(context).playbackClockSyncStarted,
                type: NotificationType.info,
              );
            },
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).playbackBackgroundGroup,
        children: [
          SettingsAction(
            icon: Icons.battery_saver_rounded,
            title: L.of(context).playbackAllowBackground,
            subtitle: L.of(context).playbackAllowBackgroundHint,
            onTap: _requestBackgroundPermissions,
          ),
          SettingsAction(
            icon: Icons.settings_applications_outlined,
            title: L.of(context).playbackAutostart,
            subtitle: L.of(context).playbackAutostartHint,
            onTap: _openAutostartSettings,
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).playbackQualityGroup,
        children: [
          SettingsAction(
            icon: Icons.graphic_eq_rounded,
            title: L.of(context).playbackSpotifySettings,
            subtitle: L.of(context).playbackSpotifySettingsHint,
            onTap: () => showAppNotification(
              context,
              message: L.of(context).playbackSpotifySettingsPath,
              type: NotificationType.info,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _sessionsSection(BuildContext context) {
    final sessions = context.watch<SessionProvider>();

    final active = sessions.sessions.where((s) => s.isActive).toList();
    final invites = sessions.invites;

    return [
      SettingsGroup(
        title: active.isEmpty
            ? L.of(context).sessionsActive
            : L.of(context).sessionsActiveCount(active.length),
        children: [
          if (active.isEmpty)
            SettingsInfo(
              icon: Icons.headphones_outlined,
              title: L.of(context).sessionsNothingPlaying,
              subtitle: L.of(context).sessionsNothingPlayingHint,
            )
          else
            for (final session in active)
              SettingsAction(
                icon: Icons.headphones_rounded,
                title: session.name,
                subtitle: L.of(context).sessionsRunningNow,
                trailing: TextButton(
                  onPressed: () => _confirmEndSession(context, session.id, session.name),
                  child: Text(L.of(context).commonFinish),
                ),
                onTap: () {
                  // Открываем сессию тем же путём, что и остальные экраны:
                  // провайдер просит показать, а решает главный экран.
                  sessions.requestOpenSession({'id': session.id, 'name': session.name});
                  Navigator.of(context).maybePop();
                },
              ),
        ],
      ),

      if (invites.isNotEmpty)
        SettingsGroup(
          title: L.of(context).invitesCount(invites.length),
          children: [
            SettingsAction(
              icon: Icons.mark_email_unread_rounded,
              title: L.of(context).invitesWaiting(invites.length),
              subtitle: L.of(context).sessionsOpenList,
              chevron: true,
              onTap: () => Navigator.of(context).pushNamed('/session/invites'),
            ),
          ],
        ),

      SettingsGroup(
        title: L.of(context).sessionsDuringGroup,
        children: [
          SettingsFlagSwitch(
            icon: Icons.open_in_full_rounded,
            title: L.of(context).sessionsAutoOpenPlayer,
            subtitle: L.of(context).sessionsAutoOpenPlayerHint,
            flagKey: StoreKeys.autoOpenPlayer,
            defaultValue: true,
          ),
          SettingsFlagSwitch(
            icon: Icons.screen_lock_portrait_outlined,
            title: L.of(context).sessionsKeepScreenOn,
            subtitle: L.of(context).sessionsKeepScreenOnHint,
            flagKey: StoreKeys.keepScreenOn,
            defaultValue: true,
          ),
          SettingsFlagSwitch(
            icon: Icons.help_outline_rounded,
            title: L.of(context).sessionsConfirmEnd,
            subtitle: L.of(context).sessionsConfirmEndHint,
            flagKey: StoreKeys.confirmEndSession,
            defaultValue: true,
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).sessionsWhoCanInvite,
        children: [
          const _InviteScopeTile(),
          SettingsAction(
            icon: Icons.block_rounded,
            title: L.of(context).privacyBlocked,
            subtitle: L.of(context).sessionsBlockedHint,
            chevron: true,
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

  Future<void> _confirmEndSession(
    BuildContext context,
    String sessionId,
    String name,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.stop_circle_outlined,
      title: L.of(context).sessionsEndTitle,
      message: L.of(context).sessionEndMessage(name),
      confirmLabel: L.of(context).commonFinish,
    );

    if (!confirmed || !mounted) return;

    try {
      await context.read<SessionProvider>().endSession(sessionId);
      if (!mounted) return;
      showSuccess(context, L.of(context).sessionsEnded);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  static const Map<String, Map<String, bool>> _privacyPresets = {
    'open': {
      'isFriendsHidden': false,
      'isActivityHidden': false,
      'isOnlineHidden': false,
      'isSearchHidden': false,
    },
    'friends': {
      'isFriendsHidden': false,
      'isActivityHidden': false,
      'isOnlineHidden': false,
      'isSearchHidden': true,
    },
    'hidden': {
      'isFriendsHidden': true,
      'isActivityHidden': true,
      'isOnlineHidden': true,
      'isSearchHidden': true,
    },
  };

  String? _currentPreset(User? user) {
    if (user == null) return null;
    final current = {
      'isFriendsHidden': user.isFriendsHidden,
      'isActivityHidden': user.isActivityHidden,
      'isOnlineHidden': user.isOnlineHidden,
      'isSearchHidden': user.isSearchHidden,
    };

    for (final entry in _privacyPresets.entries) {
      if (mapEquals(entry.value, current)) return entry.key;
    }
    return null;
  }

  List<Widget> _privacySection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final preset = _currentPreset(user);

    return [
      SettingsGroup(
        title: L.of(context).privacyWhatIsVisible,
        children: [_PrivacySummary(user: user)],
      ),

      SettingsGroup(
        title: L.of(context).privacyQuickMode,
        children: [
          SettingsPanel(
            child: PillSelector(
              padding: EdgeInsets.zero,
              labels: [
                L.of(context).privacyPresetOpen,
                L.of(context).privacyPresetFriends,
                L.of(context).privacyPresetHidden,
              ],
              // -1, когда сочетание своё: ни одна таблетка не подсвечена.
              selectedIndex: switch (preset) {
                'open' => 0,
                'friends' => 1,
                'hidden' => 2,
                _ => -1,
              },
              onSelected: (index) {
                final key = ['open', 'friends', 'hidden'][index];
                _updatePrivacy(_privacyPresets[key]!);
              },
            ),
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).privacyDetailed,
        children: [
          SettingsSwitch(
            icon: Icons.person_search_outlined,
            title: L.of(context).privacyHideSearch,
            subtitle: L.of(context).privacyHideSearchHint,
            value: user?.isSearchHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isSearchHidden': v}),
          ),
          SettingsSwitch(
            icon: Icons.visibility_off_rounded,
            title: L.of(context).privacyHideOnline,
            subtitle: L.of(context).privacyHideOnlineHint,
            value: user?.isOnlineHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isOnlineHidden': v}),
          ),
          SettingsSwitch(
            icon: Icons.timeline_rounded,
            title: L.of(context).privacyHideActivity,
            subtitle: L.of(context).privacyHideActivityHint,
            value: user?.isActivityHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isActivityHidden': v}),
          ),
          SettingsSwitch(
            icon: Icons.people_outline_rounded,
            title: L.of(context).privacyHideFriends,
            subtitle: L.of(context).privacyHideFriendsHint,
            value: user?.isFriendsHidden ?? false,
            onChanged: (v) => _updatePrivacy({'isFriendsHidden': v}),
          ),
        ],
      ),

      SettingsGroup(
        title: L.of(context).privacyBlockList,
        children: [_BlockedSummaryTile(onOpen: () => _openBlocked(context))],
      ),

      // Ниже — не настройки, а сведения: переключать здесь нечего, и строки
      // не притворяются кнопками.
      SettingsGroup(
        title: L.of(context).privacyAlwaysVisible,
        children: [
          SettingsInfo(
            icon: Icons.badge_outlined,
            title: L.of(context).privacyNameAndAvatar,
            subtitle: L.of(context).privacyNameAndAvatarHint,
            trailing: const Icon(Icons.lock_outline_rounded),
          ),
          SettingsInfo(
            icon: Icons.headphones_outlined,
            title: L.of(context).privacySessionParticipation,
            subtitle: L.of(context).privacySessionParticipationHint,
            trailing: const Icon(Icons.lock_outline_rounded),
          ),
          SettingsInfo(
            icon: Icons.history_rounded,
            title: L.of(context).privacyHistory,
            // Не ограничение, а наоборот — гарантия. Стоит здесь же, потому
            // что человек ищет ответ на тот же вопрос: «а это видно?»
            subtitle: L.of(context).privacyHistoryHint,
            trailing: const Icon(Icons.visibility_off_outlined),
          ),
        ],
      ),
    ];
  }

  void _openBlocked(BuildContext context) => _openChild(
        context,
        (ctx, onBack) => BlockedUsersScreen(
          embedded: ctx.isWideWindow,
          onBack: onBack,
        ),
      );

  List<Widget> _dataSection(BuildContext context) {
    return [
      SettingsGroup(
        title: L.of(context).dataOnThisDevice,
        children: [
          SettingsFlagSwitch(
            icon: Icons.bolt_outlined,
            title: L.of(context).dataPrefetch,
            subtitle: L.of(context).dataPrefetchHint,
            flagKey: StoreKeys.prefetchOnStart,
            defaultValue: true,
          ),
          SettingsAction(
            icon: Icons.cleaning_services_outlined,
            title: L.of(context).dataSavedLists,
            subtitle: _localCacheSummary(),
            onTap: () async {
              await LocalStore.clearAll();
              if (!mounted) return;
              setState(() {});
              showSuccess(context, L.of(context).dataSavedListsCleared);
            },
          ),
          const _ImageCacheTile(),
        ],
      ),
      SettingsGroup(
        title: L.of(context).dataOnServer,
        children: [
          SettingsAction(
            icon: Icons.history_rounded,
            title: L.of(context).privacyHistory,
            subtitle: L.of(context).dataHistoryHint,
            chevron: true,
            onTap: widget.onOpenHistory ??
                () => _openChild(
                      context,
                      (ctx, onBack) => PlayHistoryScreen(
                        embedded: ctx.isWideWindow,
                        onBack: onBack,
                      ),
                    ),
          ),
          const _ExportDataTile(),
          SettingsAction(
            icon: Icons.shield_outlined,
            title: L.of(context).dataWhatIsStored,
            subtitle: L.of(context).dataWhatIsStoredHint,
            chevron: true,
            onTap: () => _openChild(
              context,
              (ctx, onBack) => PrivacyPolicyScreen(
                embedded: ctx.isWideWindow,
                onBack: onBack,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  String _notificationsSummary(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final off = [
      if (!settings.notification('friendRequests')) L.of(context).notificationsOffRequests,
      if (!settings.notification('sessionInvites')) L.of(context).notificationsOffInvites,
    ];

    if (off.isEmpty) return L.of(context).notificationsAllOn;
    if (off.length == 2) return L.of(context).notificationsAllOff;
    return L.of(context).notificationsOffOne(off.first);
  }

  List<Widget> _notificationsSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    Future<void> toggle(String key, bool value) async {
      try {
        await context.read<SettingsProvider>().setNotification(key, value);
      } catch (err) {
        if (!mounted) return;
        showError(context, err);
      }
    }

    return [
      SettingsGroup(
        title: L.of(context).notificationsGroup,
        children: [
          SettingsSwitch(
            icon: Icons.person_add_alt_1_outlined,
            title: L.of(context).notificationsFriendRequests,
            subtitle: L.of(context).notificationsFriendRequestsHint,
            value: settings.notification('friendRequests'),
            onChanged: (v) => toggle('friendRequests', v),
          ),
          SettingsSwitch(
            icon: Icons.mark_email_unread_outlined,
            title: L.of(context).notificationsSessionInvites,
            subtitle: L.of(context).notificationsSessionInvitesHint,
            value: settings.notification('sessionInvites'),
            onChanged: (v) => toggle('sessionInvites', v),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          bottom: AppSpacing.lg,
        ),
        child: Text(
          L.of(context).notificationsHint,
          style: context.texts.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ),
    ];
  }

  List<Widget> _securitySection(BuildContext context) {
    return [
      SettingsGroup(
        title: L.of(context).securitySessionsGroup,
        children: [
          SettingsAction(
            icon: Icons.devices_rounded,
            title: L.of(context).securityDevices,
            subtitle: L.of(context).securityDevicesHint,
            chevron: true,
            onTap: () => _openChild(
              context,
              (ctx, onBack) => DevicesScreen(
                embedded: ctx.isWideWindow,
                onBack: onBack,
              ),
            ),
          ),
          SettingsInfo(
            icon: Icons.vpn_key_outlined,
            title: L.of(context).securitySignInMethod,
            subtitle: _signInSummary(context),
            trailing: const Icon(Icons.lock_outline_rounded),
          ),
        ],
      ),

      // Опасная зона отделена и заголовком, и рамкой: сюда не должна
      // соскользнуть рука, листающая обычные настройки.
      SettingsGroup(
        title: L.of(context).securityDangerZone,
        tone: SettingsTone.danger,
        children: [
          SettingsAction(
            icon: Icons.logout_rounded,
            title: L.of(context).commonSignOut,
            subtitle: L.of(context).securitySignOutThisDevice,
            onTap: () => _confirmLogout(context),
          ),
          SettingsAction(
            icon: Icons.phonelink_erase_rounded,
            title: L.of(context).securitySignOutEverywhere,
            subtitle: L.of(context).securitySignOutEverywhereHint,
            danger: true,
            onTap: () => _confirmLogoutEverywhere(context),
          ),
          SettingsAction(
            icon: Icons.delete_outline_rounded,
            title: L.of(context).securityDeleteAccount,
            subtitle: L.of(context).securityDeleteAccountHint,
            danger: true,
            onTap: () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    ];
  }

  /// Как человек входит в аккаунт. Пароля в системе нет — вход только через
  /// внешние сервисы, поэтому «сменить пароль» здесь предлагать нечего.
  String _signInSummary(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    if (user?.spotifyConnected == true) return L.of(context).securitySignInSpotifyGoogle;
    return L.of(context).securitySignInGoogle;
  }

  Future<void> _confirmLogoutEverywhere(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.phonelink_erase_rounded,
      title: L.of(context).securitySignOutEverywhereTitle,
      message: L.of(context).securitySignOutEverywhereMessage,
      confirmLabel: L.of(context).securitySignOutEverywhereConfirm,
    );

    if (!confirmed || !mounted) return;

    try {
      await context.read<PlaybackProvider>().stopAndClear();
      if (!mounted) return;

      context.read<PlaylistsProvider>().reset();

      await context.read<AuthProvider>().logoutEverywhere();
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  String _localCacheSummary() {
    final counts = <String>[];
    final friends = LocalStore.readList(StoreKeys.friends).length;
    final sessions = LocalStore.readList(StoreKeys.sessions).length;
    if (friends > 0) counts.add(L.of(context).cacheFriendsCount(friends));
    if (sessions > 0) counts.add(L.of(context).cacheSessionsCount(sessions));

    if (counts.isEmpty) return L.of(context).dataNothingSaved;

    final stamps = [
      LocalStore.savedAt(StoreKeys.friends),
      LocalStore.savedAt(StoreKeys.sessions),
    ].whereType<DateTime>().toList()
      ..sort();

    if (stamps.isEmpty) return counts.join(' · ');
    return '${counts.join(' · ')} · ${_ago(stamps.last)}';
  }

  String _ago(DateTime moment) {
    final diff = DateTime.now().difference(moment);
    if (diff.inMinutes < 1) return L.of(context).dataUpdatedJustNow;
    if (diff.inMinutes < 60) return L.of(context).updatedMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return L.of(context).updatedHoursAgo(diff.inHours);
    return L.of(context).updatedDaysAgo(diff.inDays);
  }

  List<Widget> _aboutSection(BuildContext context) {
    return [
      const _AboutHeader(),
      const SizedBox(height: AppSpacing.lg),
      SettingsGroup(
        title: L.of(context).aboutLegalGroup,
        children: [
          SettingsAction(
            icon: Icons.shield_outlined,
            title: L.of(context).aboutDataPrivacy,
            subtitle: L.of(context).aboutDataPrivacyHint,
            chevron: true,
            onTap: () => _openChild(
              context,
              (ctx, onBack) => PrivacyPolicyScreen(
                embedded: ctx.isWideWindow,
                onBack: onBack,
                onOpenFullText: () => _openChild(
                  context,
                  (innerCtx, innerBack) => LegalDocumentScreen(
                    title: L.of(context).aboutPrivacyPolicy,
                    assetPath: Config.privacyPolicyAsset,
                    url: Config.privacyPolicyUrl,
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
            title: L.of(context).aboutTerms,
            subtitle: L.of(context).aboutTermsHint,
            chevron: true,
            onTap: () => _openChild(
              context,
              (ctx, onBack) => LegalDocumentScreen(
                title: L.of(context).aboutTerms,
                assetPath: Config.termsAsset,
                url: Config.termsUrl,
                embedded: ctx.isWideWindow,
                onBack: onBack,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  String _clockSyncSummary() {
    final socket = SocketService();
    final offset = socket.masterOffsetMs;
    if (offset == 0) return L.of(context).playbackClockUnknown;

    final sign = offset > 0 ? '+' : '';
    return L.of(context).clockSummary('$sign$offset', socket.rttMs);
  }

  static String _formatPublicId(String id) =>
      id.length == 8 ? '${id.substring(0, 4)} ${id.substring(4)}' : id;

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
      showSuccess(context, L.of(context).nameUpdated);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.warning_amber_rounded,
      title: L.of(context).securityDeleteAccountTitle,
      message: L.of(context).deleteAccountMessage,
      confirmLabel: L.of(context).commonDelete,
    );

    if (!confirmed || !mounted) return;

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
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: L.of(context).securitySignOutTitle,
      message: L.of(context).securitySignOutMessage,
      confirmLabel: L.of(context).commonSignOut,
    );

    if (!confirmed || !mounted) return;

    // Останавливаем воспроизведение до выхода: проигрыватель переживает
    // смену аккаунта, и без этого следующий вошедший видел бы панель с
    // чужим треком.
    await context.read<PlaybackProvider>().stopAndClear();
    if (!mounted) return;

    context.read<PlaylistsProvider>().reset();

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
      message: L.of(context).playbackPermissionsHint,
      type: NotificationType.info,
    );
  }

  Future<void> _openAutostartSettings() async {
    final opened = await SessionForegroundService.openAutostartSettings();
    if (!mounted || opened) return;
    showAppNotification(
      context,
      message: L.of(context).playbackAutostartHint2,
      type: NotificationType.info,
    );
  }
}




/// Состояние подключения Spotify.
///
/// Отдельная плитка, а не строка в списке: наличие записи о подключении в
/// профиле ничего не говорит о том, живо ли оно. Доступ можно отозвать из
/// самого Spotify, и тогда приложение продолжало показывать «Подключён»,
/// пока человек не попробует включить трек и не получит невнятную ошибку.
/// Плитка спрашивает сервер, а тот проверяет токен настоящим запросом.
/// Выгрузка своих данных в файл.
///
/// Файл собирает сервер: только он знает всё, что хранится о человеке.
/// Клиент выбирает, куда положить, и ничего не додумывает.
class _ExportDataTile extends StatefulWidget {
  const _ExportDataTile();

  @override
  State<_ExportDataTile> createState() => _ExportDataTileState();
}

class _ExportDataTileState extends State<_ExportDataTile> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final bytes = await context.read<AuthProvider>().api.exportMyData();
      if (!mounted) return;

      final fileName =
          'syncm-data-${DateTime.now().toIso8601String().split('T').first}.json';
      final saved = await saveBytesToFile(fileName, bytes);
      if (!mounted) return;

      if (saved == null) return; // от сохранения отказались
      showSuccess(context, L.of(context).exportSaved(saved));
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsAction(
      icon: Icons.download_outlined,
      title: L.of(context).dataExport,
      subtitle: L.of(context).dataExportHint,
      enabled: !_busy,
      trailing: _busy ? const _RowSpinner() : null,
      onTap: _export,
    );
  }
}

/// Язык интерфейса.
///
/// «Системный» — не отдельный перевод, а отказ выбирать: приложение берёт
/// язык устройства и откатывается к русскому, если такого перевода нет.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  static const _codes = ['system', 'ru', 'en'];

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final index = _codes.indexOf(locale.language);

    return SettingsPanel(
      icon: Icons.translate_rounded,
      title: L.of(context).appearanceLanguage,
      description: L.of(context).appearanceLanguageHint,
      child: PillSelector(
        padding: EdgeInsets.zero,
        labels: [L.of(context).commonSystem, 'Русский', 'English'],
        selectedIndex: index < 0 ? 0 : index,
        onSelected: (i) =>
            context.read<LocaleProvider>().setLanguage(_codes[i]),
      ),
    );
  }
}

/// Кто может звать в сессию.
///
/// Ограничение соблюдает сервер: он отказывает в создании сессии, если
/// приглашения отключены. Интерфейс лишь показывает и меняет значение.
class _InviteScopeTile extends StatefulWidget {
  const _InviteScopeTile();

  @override
  State<_InviteScopeTile> createState() => _InviteScopeTileState();
}

class _InviteScopeTileState extends State<_InviteScopeTile> {
  bool _saving = false;

  static const _scopes = ['friends', 'nobody'];

  Future<void> _select(int index) async {
    final scope = _scopes[index];
    final settings = context.read<SettingsProvider>();
    if (settings.inviteScope == scope || _saving) return;

    setState(() => _saving = true);
    try {
      await settings.setInviteScope(scope);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final index = _scopes.indexOf(settings.inviteScope);

    // Заголовок несёт группа — плитке остаётся пояснение к текущему выбору.
    return SettingsPanel(
      icon: Icons.mark_email_unread_outlined,
      description: settings.inviteScope == 'nobody'
          ? L.of(context).inviteScopeNobodyHint
          : L.of(context).inviteScopeFriendsHint,
      child: PillSelector(
        padding: EdgeInsets.zero,
        labels: [L.of(context).commonFriends, L.of(context).commonNobody],
        selectedIndex: index < 0 ? 0 : index,
        onSelected: _saving ? _ignore : _select,
      ),
    );
  }

  static void _ignore(int _) {}
}

/// Кэш обложек: сколько занято и очистка.
///
/// Считает и оперативную память, и диск — очистка удаляет и то, и другое.
class _ImageCacheTile extends StatefulWidget {
  const _ImageCacheTile();

  @override
  State<_ImageCacheTile> createState() => _ImageCacheTileState();
}

class _ImageCacheTileState extends State<_ImageCacheTile> {
  int? _diskBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final bytes = await imageCacheDiskBytes();
    if (!mounted) return;
    setState(() => _diskBytes = bytes);
  }

  String _size(int bytes) {
    final l = L.of(context);
    if (bytes >= 1024 * 1024) {
      return l.sizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
    }
    if (bytes >= 1024) return l.sizeKilobytes((bytes / 1024).round());
    return l.sizeBytes(bytes);
  }

  String get _subtitle {
    final memory = PaintingBinding.instance.imageCache;
    final disk = _diskBytes;

    if (disk == null) {
      // Диск посчитать не вышло (или это браузер) — не выдумываем цифру.
      if (memory.currentSize == 0) return L.of(context).commonEmpty;
      return L.of(context).cacheInMemory(_size(memory.currentSizeBytes));
    }

    if (disk == 0 && memory.currentSize == 0) return L.of(context).commonEmpty;

    return L.of(context).cacheOnDisk(
      _size(disk),
      _size(memory.currentSizeBytes),
    );
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await AppImageCache.clear();
      await _measure();
      if (!mounted) return;
      showSuccess(context, L.of(context).dataImageCacheCleared);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsAction(
      icon: Icons.image_outlined,
      title: L.of(context).dataImageCache,
      subtitle: _subtitle,
      enabled: !_clearing,
      trailing: _clearing ? const _RowSpinner() : null,
      onTap: _clear,
    );
  }
}

/// Индикатор занятости в строке настройки: размер под 20-точечную иконку,
/// чтобы строка не подпрыгивала, пока идёт работа.
class _RowSpinner extends StatelessWidget {
  const _RowSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// Точка состояния: зелёная — связь есть, серая — нет.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Шапка страницы «О приложении».
///
/// Раньше версия была обычной строкой списка и терялась среди ссылок.
/// Знак, название и версия — то, зачем сюда заходят, — стоят отдельно.
class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        children: [
          // Фирменный знак приложения в состоянии покоя: он же встречает на
          // главном экране, и здесь не анимируется.
          const SyncMark(size: 84),
          const SizedBox(height: AppSpacing.lg),
          Text('SyncM', style: texts.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            L.of(context).aboutVersion(Config.appVersion),
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              L.of(context).loginTagline,
              textAlign: TextAlign.center,
              style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotifyTile extends StatefulWidget {
  const _SpotifyTile({required this.fallbackConnected});

  /// Что известно из профиля. Показывается, пока идёт проверка и если
  /// проверка не удалась — лучше приблизительно, чем пусто.
  final bool fallbackConnected;

  @override
  State<_SpotifyTile> createState() => _SpotifyTileState();
}

enum _SpotifyLink { checking, connected, needsReauth, disconnected, unknown }

class _SpotifyTileState extends State<_SpotifyTile> {
  _SpotifyLink _state = _SpotifyLink.checking;
  String? _accountName;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check({bool refresh = true}) async {
    if (mounted) setState(() => _state = _SpotifyLink.checking);

    try {
      final status =
          await context.read<AuthProvider>().api.getSpotifyStatus(refresh: refresh);
      if (!mounted) return;

      setState(() {
        _accountName = status['displayName'] as String?;
        _state = switch (status['state']) {
          'connected' => _SpotifyLink.connected,
          'needs_reauth' => _SpotifyLink.needsReauth,
          'disconnected' => _SpotifyLink.disconnected,
          // Сервер старой версии не присылает state — падаем на connected.
          _ => (status['connected'] == true)
              ? _SpotifyLink.connected
              : _SpotifyLink.disconnected,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _SpotifyLink.unknown);
    }
  }

  String get _subtitle => switch (_state) {
        _SpotifyLink.checking => L.of(context).spotifyChecking,
        _SpotifyLink.connected =>
          _accountName == null
              ? L.of(context).spotifyConnected
              : L.of(context).spotifyConnectedAs(_accountName!),
        _SpotifyLink.needsReauth =>
          L.of(context).spotifyNeedsReauth,
        _SpotifyLink.disconnected => L.of(context).spotifyNotConnected,
        _SpotifyLink.unknown => widget.fallbackConnected
            ? L.of(context).spotifyCheckFailed
            : L.of(context).spotifyNotConnected,
      };

  String get _actionLabel => switch (_state) {
        _SpotifyLink.connected => L.of(context).spotifyDisconnect,
        _SpotifyLink.needsReauth => L.of(context).spotifyReconnect,
        _SpotifyLink.disconnected => L.of(context).spotifyConnect,
        _SpotifyLink.unknown => L.of(context).spotifyCheck,
        _SpotifyLink.checking => '',
      };

  Future<void> _act() async {
    switch (_state) {
      case _SpotifyLink.checking:
        return;
      case _SpotifyLink.unknown:
        await _check();
        return;
      case _SpotifyLink.connected:
        await disconnectSpotify(context);
      case _SpotifyLink.needsReauth:
      case _SpotifyLink.disconnected:
        await connectSpotify(context);
    }

    if (!mounted) return;
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final warning = _state == _SpotifyLink.needsReauth;

    return SettingsAction(
      icon: warning ? Icons.link_off_rounded : Icons.music_note_rounded,
      title: 'Spotify',
      subtitle: _subtitle,
      enabled: _state != _SpotifyLink.checking,
      trailing: _state == _SpotifyLink.checking
          ? const _RowSpinner()
          : Text(
              _actionLabel,
              style: context.texts.labelLarge?.copyWith(
                color: warning ? colors.error : context.roles.mine,
              ),
            ),
      onTap: _act,
    );
  }
}

/// Шапка настроек: кто вошёл и чем это подтверждено.
///
/// Раньше аватар с именем стояли по центру колонкой и занимали треть первого
/// экрана — до первой настройки приходилось прокручивать. Горизонтальная
/// карточка говорит то же самое втрое ниже и одинаково хорошо ложится и на
/// телефон, и на широкое окно.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.avatarUrl,
    required this.displayName,
    required this.spotifyConnected,
    required this.isUploading,
    required this.onEdit,
  });

  final String? avatarUrl;
  final String displayName;
  final bool spotifyConnected;
  final bool isUploading;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final roles = context.roles;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          Stack(
            children: [
              // Нажатие на сам аватар разворачивает его на весь экран, а
              // изменить фотографию можно кнопкой в углу. Раньше нажатие в
              // любое место сразу открывало выбор файла, и посмотреть свою
              // аватарку целиком было невозможно.
              TappableAvatar(
                imageUrl: avatarUrl,
                radius: 34,
                showRing: true,
                title: displayName,
                heroTag: 'settings-avatar',
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Material(
                  color: colors.primary,
                  shape: CircleBorder(
                    side: BorderSide(color: colors.surfaceContainerLow, width: 2.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onEdit,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: isUploading
                          ? Padding(
                              padding: const EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.photo_camera_rounded,
                              color: colors.onPrimary,
                              size: 15,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: texts.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: spotifyConnected
                            ? roles.spotify
                            : colors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        spotifyConnected
                            ? L.of(context).spotifyConnectedShort
                            : L.of(context).spotifyNotConnectedShort,
                        style: texts.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Выбор темы: три образца вместо трёх слов.
///
/// Кнопки «Система / Светлая / Тёмная» ничего не показывали — приходилось
/// переключать и смотреть, что стало с приложением. Образец рисует ту же
/// картинку, что человек увидит: фон, карточку, текст и акцент.
class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker();

  static const _modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  String _label(BuildContext context, ThemeMode mode) => switch (mode) {
        ThemeMode.light => L.of(context).themeLight,
        ThemeMode.dark => L.of(context).themeDark,
        ThemeMode.system => L.of(context).commonSystem,
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final accent = context.watch<AppearanceProvider>().accent;

    return SettingsPanel(
      icon: Icons.contrast_rounded,
      title: L.of(context).appearanceTheme,
      description: _label(context, theme.themeMode),
      child: Row(
        children: [
          for (final mode in _modes) ...[
            if (mode != _modes.first) const SizedBox(width: AppSpacing.sm + 4),
            Expanded(
              child: _ThemeModeCard(
                mode: mode,
                accent: accent,
                label: _label(context, mode),
                selected: theme.themeMode == mode,
                onTap: () => context.read<ThemeProvider>().setThemeMode(mode),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.mode,
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final AccentColor accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = selected
        ? context.roles.mine
        : colors.outlineVariant.withValues(alpha: 0.8);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Pressable(
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.medium,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.short,
              curve: AppMotion.enter,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: AppRadius.medium,
                border: Border.all(
                  color: border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1.25,
                    child: ClipRRect(
                      borderRadius: AppRadius.small,
                      child: _preview(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelMedium?.copyWith(
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: context.roles.mine,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    return switch (mode) {
      ThemeMode.light => _half(Brightness.light),
      ThemeMode.dark => _half(Brightness.dark),
      // «Система» — половина светлая, половина тёмная: приложение возьмёт ту,
      // что стоит в устройстве.
      ThemeMode.system => Row(
          children: [
            Expanded(child: _half(Brightness.light)),
            Expanded(child: _half(Brightness.dark)),
          ],
        ),
    };
  }

  /// Половинка образца в заданной яркости.
  ///
  /// Цвета берутся из той же палитры, которую применит приложение, — образец
  /// не может разойтись с результатом нажатия.
  Widget _half(Brightness brightness) {
    final scheme = AppTheme.previewScheme(brightness, accent);
    final ink = scheme.onSurface;

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bar(scheme.primary, 22, 5),
            const SizedBox(height: 5),
            _bar(ink.withValues(alpha: 0.85), 34, 4),
            const SizedBox(height: 4),
            _bar(ink.withValues(alpha: 0.35), 26, 4),
            const SizedBox(height: 6),
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color, double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
}


class _AudioLatencyTile extends StatelessWidget {
  const _AudioLatencyTile();

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final l = L.of(context);
    final pb = context.watch<PlaybackProvider>();
    final latency = pb.audioLatencyMs;

    return SettingsPanel(
      icon: Icons.headphones_rounded,
      title: L.of(context).latencyTitle,
      trailing: Text(
        l.latencyMilliseconds(latency),
        style: texts.labelLarge?.copyWith(color: context.roles.mine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Slider(
            value: latency.toDouble().clamp(0, 1000),
            max: 1000,
            divisions: 40, // шаг 25 мс
            label: l.latencyMilliseconds(latency),
            onChanged: (v) => pb.setAudioLatency(v.round()),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final preset in [
                (label: L.of(context).latencyWired, value: 0),
                (label: 'Bluetooth', value: 175),
                (label: L.of(context).latencySpeaker, value: 300),
              ])
                ChoiceChip(
                  label: Text(preset.label),
                  selected: latency == preset.value,
                  onSelected: (_) => pb.setAudioLatency(preset.value),
                  showCheckmark: false,
                ),
            ],
          ),
          // Кнопка сброса всегда занимает своё место, просто становится
          // неактивной: иначе при первом же движении ползунка она появлялась
          // и сдвигала содержимое карточки вниз.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: latency > 0 ? () => pb.setAudioLatency(0) : null,
              child: Text(L.of(context).commonReset),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final current = context.watch<AppearanceProvider>().accent;

    return SettingsPanel(
      icon: Icons.palette_outlined,
      title: L.of(context).appearanceAccent,
      description: _AccentDot.nameOf(context, current),
      child: Wrap(
        spacing: AppSpacing.sm + 4,
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

  /// Название цвета на языке интерфейса.
  ///
  /// В самом перечислении подпись остаётся русской и служит запасной: цвета
  /// заданы в теме, а тема о языке ничего не знает.
  static String nameOf(BuildContext context, AccentColor accent) {
    final l = L.of(context);
    return switch (accent) {
      AccentColor.olive => l.accentOlive,
      AccentColor.clay => l.accentClay,
      AccentColor.indigo => l.accentIndigo,
      AccentColor.plum => l.accentPlum,
      AccentColor.amber => l.accentAmber,
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = nameOf(context, accent);
    final colors = context.colors;

    return Semantics(
      // Название в озвучке: программам чтения с экрана цвет недоступен, и
      // без подписи все пять кружков звучали бы одинаково.
      label: name,
      selected: selected,
      button: true,
      child: Tooltip(
        message: name,
        child: Pressable(
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              // Цель нажатия — все 48 точек, а кружок внутри меньше:
              // плотный ряд крупных пятен читался как светофор.
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: AppMotion.short,
                    curve: AppMotion.enter,
                    width: selected ? 36 : 30,
                    height: selected ? 36 : 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: selected
                            ? colors.onSurface
                            : colors.outlineVariant.withValues(alpha: 0.6),
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: context.roles.onMine,
                          )
                        : null,
                  ),
                ),
              ),
            ),
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

    return SettingsPanel(
      icon: Icons.format_size_rounded,
      title: L.of(context).appearanceTextSize,
      trailing: Text(
        '${(scale * 100).round()}%',
        style: texts.labelLarge?.copyWith(color: context.roles.mine),
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
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: AppRadius.small,
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L.of(context).previewTrackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.titleSmall?.copyWith(fontSize: 14 * scale),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        L.of(context).previewArtistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(
                          fontSize: 12 * scale,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.text_fields_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
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
              Icon(
                Icons.text_fields_rounded,
                size: 22,
                color: colors.onSurfaceVariant,
              ),
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
    if (name.isEmpty) return L.of(context).nameDialogEmpty;
    if (name.length < _minLength) return L.of(context).nameDialogTooShort(_minLength);
    if (name.length > _maxLength) return L.of(context).nameDialogTooLong(_maxLength);
    if (!_allowed.hasMatch(name)) {
      return L.of(context).nameDialogCharset;
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
      title: Text(L.of(context).nameDialogTitle),
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
              labelText: L.of(context).commonName,
              counterText:
                  _controller.text.length > _maxLength - 15 ? null : '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            L.of(context).nameDialogHint,
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: _canSave ? _submit : null,
          child: Text(L.of(context).commonSave),
        ),
      ],
    );
  }
}

class _PrivacySummary extends StatelessWidget {
  const _PrivacySummary({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final u = user;

    if (u == null) return const SizedBox.shrink();

    final friendsSee = <String>[
      L.of(context).privacySummaryNameAvatar,
      if (!u.isOnlineHidden) L.of(context).privacySummaryOnline,
      if (!u.isActivityHidden) L.of(context).privacySummaryListening,
      if (!u.isFriendsHidden) L.of(context).privacySummaryFriendCount,
    ];

    final strangersSee = u.isSearchHidden
        ? L.of(context).privacySummaryNotSearchable
        : L.of(context).privacySummarySearchable;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryLine(
            icon: Icons.people_alt_rounded,
            audience: L.of(context).privacySummaryFriendsSee,
            value: friendsSee.join(', '),
            color: colors.onSurface,
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          _SummaryLine(
            icon: Icons.public_rounded,
            audience: L.of(context).privacySummaryOthers,
            value: strangersSee,
            color: colors.onSurfaceVariant,
          ),
          if (u.isOnlineHidden && u.isActivityHidden && u.isFriendsHidden) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            Text(
              L.of(context).privacyHiddenWarning,
              style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.audience,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String audience;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.sm + 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                audience,
                style: texts.labelMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(value, style: texts.bodyMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlockedSummaryTile extends StatefulWidget {
  const _BlockedSummaryTile({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_BlockedSummaryTile> createState() => _BlockedSummaryTileState();
}

class _BlockedSummaryTileState extends State<_BlockedSummaryTile> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AuthProvider>().api.getBlockedUsers();
      if (!mounted) return;
      setState(() => _count = list.length);
    } catch (err) {
      debugPrint('Не удалось получить число заблокированных: $err');
    }
  }

  String get _subtitle {
    final count = _count;
    if (count == null) return L.of(context).privacyBlockedHint;
    if (count == 0) return L.of(context).privacyBlockedNobody;

    return L.of(context).blockedPeopleCount(count);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsAction(
      icon: Icons.block_rounded,
      title: L.of(context).privacyBlocked,
      subtitle: _subtitle,
      onTap: widget.onOpen,
    );
  }
}