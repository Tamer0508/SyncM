import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
import 'package:syncm/screens/settings/play_history_screen.dart';
import 'package:syncm/screens/settings/settings_screen.dart';
import 'package:syncm/screens/session/create_session_screen.dart';
import 'package:syncm/screens/profile/profile_screen.dart';
import 'package:syncm/screens/session/session_invites_screen.dart';
import 'package:syncm/screens/session/session_results_screen.dart';
import 'package:syncm/screens/session/session_screen.dart';
import 'package:syncm/screens/friends/search_users_screen.dart';
import 'package:syncm/screens/friends/friend_requests_screen.dart';
import 'package:syncm/services/prefetch_service.dart';
import 'package:syncm/services/socket_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/playlist_actions.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable_avatar.dart';
import '../../widgets/app_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../models/sync_phase.dart';
import '../../widgets/pill_selector.dart';
import '../../widgets/sync_mark.dart';
import '../../utils/local_store.dart';
import '../../widgets/animated_notification_button.dart';
import '../../utils/error_utils.dart';
import '../../widgets/home_nav.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/now_playing_panel.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/playlists_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/friends_provider.dart';
import '../friends/friends_screen.dart';

// ---------- HomeScreen ----------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = LocalStore.readDouble(StoreKeys.startTab, defaultValue: 0)
      .round()
      .clamp(0, 2);
  Map<String, dynamic>? _selectedPlaylist;
  final _prefetch = PrefetchService();

  /// Общий ключ для стопки вкладок в обеих раскладках.
  ///
  /// Раскладки — разные ветки дерева, и при переходе через границу Flutter
  /// снёс бы вкладки и построил заново: прокрутка списков, введённый в поиск
  /// текст и раскрытые разделы терялись просто от того, что окно потянули за
  /// край. С GlobalKey элемент переезжает в новое место вместе с состоянием.
  final GlobalKey _tabsKey = GlobalKey();



  bool _creatingSession = false;

  void _clearOverlays() {
    _creatingSession = false;
    _activeFriendView = null;
    _activeSession = null;
    _sessionResults = null;

    _showingInvites = false;
    _viewingProfile = null;
    _showingOwnProfile = false;
    _showingSettings = false;
    _showingHistory = false;
    _selectedPlaylist = null;
  }

  /// Открывает наложенный экран, погасив предыдущий.
  void _openOverlay(VoidCallback apply) {
    setState(() {
      _clearOverlays();
      apply();
    });
  }
  Map<String, dynamic>? _activeSession;

  Map<String, dynamic>? _sessionResults;

  int _musicTabIndex = 0;

  /// Открыт ли список приглашений в центральной части.
  bool _showingInvites = false;

  /// Профиль друга, открытый в центральной части.
  Map<String, dynamic>? _viewingProfile;

  bool _showingOwnProfile = false;
  bool _showingSettings = false;

  bool _showingHistory = false;
  String? _activeFriendView; // 'searchL.of(context).commonOrrequests'


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Загрузка плейлистов начинается после кадра, а не из initState.
      //
      // `PlaylistsProvider.loadCustom/loadSpotify` выставляют флаг загрузки и
      // зовут notifyListeners синхронно, до первого await. Из initState это
      // приходится на фазу построения кадра: слушатели провайдера, которые
      // уже построились, получают markNeedsBuild посреди build.
      _loadAllPlaylists();

      final socket = SocketService();
      final friendsProv = context.read<FriendsProvider>();
      final sessionProv = context.read<SessionProvider>();

      friendsProv.init(socket);
      sessionProv.init(socket);

      if (LocalStore.readBool(StoreKeys.prefetchOnStart, defaultValue: true)) {
      _prefetch.warmUp(friends: friendsProv, sessions: sessionProv).then((_) {
        if (mounted) _prefetch.warmUpAvatars(context, friendsProv.friends);
      });
      }
    });
  }

  bool get _hasOverlay =>
      _showingSettings ||
      _showingHistory ||
      _showingOwnProfile ||
      _viewingProfile != null ||
      _showingInvites ||
      _activeFriendView != null ||
      _activeSession != null ||
      _creatingSession;

  void _openOwnProfile(bool isDesktop) {
    if (isDesktop) {
      _openOverlay(() => _showingOwnProfile = true);
      return;
    }
    Navigator.of(context).pushNamed('/profile');
  }

  void _openInvites(bool isDesktop) {
    if (isDesktop) {
      _openOverlay(() => _showingInvites = true);
      return;
    }
    Navigator.of(context).pushNamed('/session/invites');
  }

  Future<void> _openSession(String sessionId) async {
  try {
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    final sessions = await api.getMySessions();
    final session = (sessions).firstWhere(
      (s) => s['id'] == sessionId,
      orElse: () => null,
    );
    if (session == null || !mounted) return;
    final data = Map<String, dynamic>.from(session);

    if (!context.isWideWindow) {
      await Navigator.of(context).pushNamed('/session', arguments: data);
      return;
    }

    _openOverlay(() => _activeSession = data);
  } catch (e) {
    // showError вместо текста исключения: пользователю показывались
    // служебные строки вида «ApiException: ... (500) [Prisma...]».
    if (mounted) showError(context, e);
  }
}

  Future<void> _loadAllPlaylists({bool refresh = false}) async {
    try {
      await context.read<PlaylistsProvider>().loadAll(refresh: refresh);
    } catch (e) {
      // showError сам молчит про 429 и внутренние сбои, поэтому проверку
      // suppressUiNotification повторять здесь не нужно.
      if (mounted) showError(context, e);
    }
  }

  /// Вкладка «Сейчас» — что происходит прямо сейчас.
  ///
  /// Раньше это была свалка: приветствие, лента плейлистов, приглашения и
  /// только потом активные сессии — то есть то, ради чего приложение и
  /// существует, лежало третьим блоком ниже сгиба. Плейлисты переехали в
  /// свою вкладку, а здесь осталось только текущее состояние.
  Widget _buildHomeTab() {
    final isDesktop = context.isWideWindow;
    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    void startSession() {
      if (isDesktop) {
        _openOverlay(() => _creatingSession = true);
      } else {
        Navigator.of(context).pushNamed('/session/create');
      }
    }

    final child = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Consumer<SessionProvider>(
          builder: (context, prov, _) {
            final invites = prov.invites;
            final sessions = prov.sessions;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Приглашения первыми: это единственное здесь, что требует
                // ответа прямо сейчас, и ждать его не должно ничто другое.
                if (invites.isNotEmpty) ...[
                  _SectionHeader(
                    title: L.of(context).homeInvitedYou,
                    badgeCount: invites.length,
                    action: TextButton(
                      onPressed: () => _openInvites(isDesktop),
                      child: Text(L.of(context).homeFilterAll),
                    ),
                  ),
                  ...invites.take(2).map((invite) {
                    final hostName = prov.hostNameForInvite(invite) ?? L.of(context).homeFilterFriend;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _HomeTile(
                        icon: Icons.mail_outline_rounded,
                        title: invite['name'] as String? ?? L.of(context).homeSession,
                        subtitle: L.of(context).homeInviteFrom(hostName),
                        onTap: () => _openInvites(isDesktop),
                      ),
                    );
                  }),
                ],

                if (prov.loading && sessions.isEmpty)
                  const SkeletonSessionCard()
                else if (sessions.isEmpty)
                  _StartSessionCard(onStart: startSession)
                else ...[
                  _SectionHeader(
                    title: L.of(context).homeNowListening,
                    action: TextButton(
                      onPressed: prov.loading ? null : prov.fetchMySessions,
                      child: Text(L.of(context).commonRefresh),
                    ),
                  ),
                  ...sessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _HomeTile(
                        icon: Icons.graphic_eq_rounded,
                        title: session.name,
                        subtitle: L.of(context).homeTapToOpen,
                        highlighted: true,
                        onTap: () => _openSession(session.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: startSession,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(L.of(context).homeAnotherSession),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );

    if (!enablePullToRefresh) return child;

    return RefreshIndicator(
      onRefresh: () async {
        final sessions = context.read<SessionProvider>();
        await Future.wait([
          sessions.fetchMySessions(),
          sessions.fetchInvites(),
        ]);
      },
      child: child,
    );
  }

  /// Вкладка «Музыка» — плейлисты, свои и из Spotify.
  ///
  /// Раньше лента плейлистов жила на главной высотой в 208 точек: карточки
  /// обрезались, названия не помещались, а прокручивать её приходилось вбок
  /// внутри вертикального списка. Собственная вкладка снимает это
  /// ограничение — плейлисты показываются сеткой во всю высоту.
  Widget _buildMusicTab() {
    return Column(
      children: [
        PillSelector(
          labels: [L.of(context).homeFilterMine, 'Spotify'],
          selectedIndex: _musicTabIndex,
          onSelected: (index) => setState(() => _musicTabIndex = index),
        ),
        Expanded(child: _buildPlaylistsTab(_musicTabIndex == 0)),
      ],
    );
  }


  Widget _buildPlaylistsTab(bool isCustom) {
    final provider = context.watch<PlaylistsProvider>();
    final playlists = isCustom ? provider.custom : provider.spotify;
    final loading = isCustom ? provider.loadingCustom : provider.loadingSpotify;

    // Заглушка занимает место списка, а не всей вкладки: шапка со створкой
    // «создать плейлист» остаётся на месте, и содержимое встаёт туда же, где
    // только что мерцали заглушки.
    final showSkeleton = loading && playlists.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCustom)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: _CreatePlaylistTile(onTap: _createCustomPlaylist),
          ),
        Expanded(
          child: showSkeleton
              ? const SkeletonPlaylistList()
              : playlists.isEmpty
                  ? _buildEmptyPlaylists(isCustom)
                  : _buildPlaylistList(playlists, isCustom: isCustom),
        ),
      ],
    );
  }

  Widget _buildEmptyPlaylists(bool isCustom) {
    if (isCustom) {
      return EmptyState(
        icon: Icons.playlist_add_rounded,
        title: L.of(context).homeNoOwnPlaylists,
        message: L.of(context).homeNoOwnPlaylistsHint,
      );
    }

    return EmptyState(
      icon: Icons.link_rounded,
      title: L.of(context).homeSpotifyUnavailable,
      message: L.of(context).homeSpotifyUnavailableHint,
      actionLabel: L.of(context).homeConnectSpotify,
      onAction: () => _openOwnProfile(context.isWideWindow),
    );
  }

  Widget _buildPlaylistList(
    List<Map<String, dynamic>> playlists, {
    required bool isCustom,
  }) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemCount: playlists.length,
      itemBuilder: (_, i) {
        final playlist = playlists[i];
        void open() => _openPlaylist(playlist, isCustom: isCustom);

        return PlaylistContextMenuRegion(
          playlist: playlist,
          onOpen: open,
          onDeleted: () => _closePlaylistIfOpen(playlist.playlistId),
          child: PlaylistCard(
            dense: true,
            name: playlist.playlistName,
            description: _playlistSubtitle(playlist),
            imageUrl: playlist.playlistImageUrl,
            onTap: open,
            trailing: PlaylistActionsButton(
              playlist: playlist,
              includeOpen: false,
              onOpen: open,
              onDeleted: () => _closePlaylistIfOpen(playlist.playlistId),
            ),
          ),
        );
      },
    );
  }

  String _playlistSubtitle(Map<String, dynamic> playlist) {
    final description = playlist.playlistDescription;
    if (description.isNotEmpty) return description;

    final count = playlist.playlistTrackCount;
    if (count == 0) return L.of(context).commonEmpty;

    return L.of(context).trackCount(count);
  }

  void _openPlaylist(Map<String, dynamic> playlist, {required bool isCustom}) {
    if (context.isWideWindow) {
      setState(() {
        _selectedPlaylist = {
          'id': playlist.playlistId,
          'name': playlist.playlistName,
          'imageUrl': playlist.playlistImageUrl,
          'isCustom': isCustom,
        };
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistTracksScreen(
          playlistId: playlist.playlistId,
          playlistName: playlist.playlistName,
          imageUrl: playlist.playlistImageUrl,
          isCustom: isCustom,
        ),
      ),
    );
  }

  void _closePlaylistIfOpen(String playlistId) {
    if (_selectedPlaylist?['id'] != playlistId) return;
    setState(() => _selectedPlaylist = null);
  }

  Future<void> _createCustomPlaylist() => showCreatePlaylistDialog(context);

  Widget _buildRightPanel() {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // select вместо Consumer: панель перестраивается только при
            // появлении или исчезновении трека, а не на каждый тик позиции
            // воспроизведения.
            child: Builder(
              builder: (context) {
                final hasTrack = context.select<PlaybackProvider, bool>(
                  (pb) => pb.currentTrack != null,
                );

                if (!hasTrack) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: AppRadius.large,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note_outlined,
                          size: 40,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.sm + 4),
                        Text(
                          L.of(context).homeNothingPlaying,
                          style: texts.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          L.of(context).homeNothingPlayingHint,
                          textAlign: TextAlign.center,
                          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return const NowPlayingPanelCompact();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Шапка широкой раскладки.
  ///
  /// Раньше здесь было четыре почти одинаковых блока — по одному на каждый
  /// режим (поиск друзей, сессия, создание сессии, обычный). Все четыре
  /// повторяли отступы, цвет фона и границу, и любое изменение оформления
  /// требовалось вносить в каждый. Теперь режимы задают только заголовок,
  /// кнопку возврата и действия справа, а сама оболочка одна.
  Widget _buildDesktopHeader() {
    final auth = context.read<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    if (_activeFriendView != null) {
      return _DesktopHeaderShell(
        title: _activeFriendView == 'search' ? L.of(context).homeSearchFriends : L.of(context).homeFriendRequests,
        onBack: () => setState(() => _activeFriendView = null),
      );
    }

    if (_activeSession != null) {
      final isHost = _activeSession!['hostId'] == auth.user?.id;
      return _DesktopHeaderShell(
        title: _activeSession!['name'] as String? ?? L.of(context).homeSession,
        onBack: () => setState(() => _activeSession = null),
        actions: [
          if (isHost)
            TextButton.icon(
              onPressed: _endActiveSession,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(L.of(context).commonFinish),
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
            ),
        ],
      );
    }

    if (_creatingSession) {
      return _DesktopHeaderShell(
        title: L.of(context).navNewSession,
        onBack: () => setState(() => _creatingSession = false),
      );
    }

    // Названия берём из того же списка, что и навигация.
    //
    // Здесь был свой массив из четырёх строк, оставшийся от прежней
    // структуры. После перехода на три вкладки он разошёлся с навигацией:
    // в «Музыке» сверху писалось «Друзья», а во «Друзьях» — «Профиль»,
    // и туда же попадали чужие кнопки в шапке.
    final tabTitles = homeDestinations(context).map((d) => d.label).toList();

    return _DesktopHeaderShell(
      title: _selectedPlaylist != null
          ? (context
                  .watch<PlaylistsProvider>()
                  .byId(_selectedPlaylist!['id'] as String? ?? '')
                  ?.playlistName ??
              _selectedPlaylist!['name'] as String? ??
              L.of(context).homePlaylist)
          : tabTitles[_currentIndex.clamp(0, tabTitles.length - 1)],
      titleKey: ValueKey(_selectedPlaylist?['id'] ?? _currentIndex),
      onBack: _selectedPlaylist != null
          ? () => setState(() => _selectedPlaylist = null)
          : null,
      actions: [
        // Кнопки друзей на своей вкладке: её индекс сменился с 1 на 2,
        // когда профиль ушёл из навигации.
        if (_currentIndex == 2) ...[
          AppIconButton(
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => _openOverlay(() => _activeFriendView = 'search'),
            tooltip: L.of(context).homeSearchFriends,
          ),
          // Счётчик заявок с той же анимацией, что и на узком экране:
          // раньше здесь была обычная иконка без числа, и о новых заявках
          // на десктопе узнать было неоткуда.
          Consumer<FriendsProvider>(
            builder: (context, prov, _) => AnimatedNotificationButton(
              icon: Icons.mail_outline_rounded,
              activeIcon: Icons.mark_email_unread_rounded,
              count: prov.unreadCount,
              tooltip: L.of(context).homeFriendRequests,
              onPressed: () => _openOverlay(() => _activeFriendView = 'requests'),
            ),
          ),
        ] else if (_currentIndex == 0) ...[
          // Обновление списка: на десктопе жеста «потянуть вниз» нет, и
          // единственным способом увидеть изменения была перезагрузка
          // страницы.
          AppIconButton(
            icon: Icons.refresh_rounded,
            onPressed: () {
              final sessions = context.read<SessionProvider>();
              sessions.fetchMySessions();
              sessions.fetchInvites();
            },
            tooltip: L.of(context).commonRefresh,
          ),
          AppIconButton(
            icon: Icons.add_rounded,
            onPressed: () => _openOverlay(() => _creatingSession = true),
            tooltip: L.of(context).homeStartSession,
          ),
        ],
        AppIconButton(
          icon: themeProvider.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          onPressed: themeProvider.toggleTheme,
          tooltip: themeProvider.isDark ? L.of(context).homeLightTheme : L.of(context).homeDarkTheme,
        ),

        // Аватар — вход в профиль и настройки.
        //
        // На узком экране он появился в шапке, а на широком его не было
        // вовсе: профиль ушёл из навигации, и попасть в него стало неоткуда.
        // Настройки при этом отрезало полностью — они открываются из профиля.
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
          child: Builder(
            builder: (context) {
              final user = context.watch<AuthProvider>().user;
              return TappableAvatar(
                imageUrl: user?.effectiveAvatarUrl,
                radius: 16,
                title: user?.displayName,
                onTapOverride: () => _openOwnProfile(true),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _endActiveSession() async {
    final sessionId = _activeSession?['id'] as String?;
    if (sessionId == null) return;

    try {
      await context.read<SessionProvider>().endSession(sessionId);
      if (!mounted) return;
      setState(() => _activeSession = null);
    } catch (err) {
      if (!mounted) return;
      // showError вместо 'Ошибка: $e': текст исключения пользователю
      // ничего не объясняет.
      showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final isDesktop = layout.showRail;
    // Вкладок теперь три в обеих раскладках — подрезать индекс не нужно.
    final unreadCount = Provider.of<FriendsProvider>(context).unreadCount;


    // Кто-то попросил открыть сессию — показываем её встроенной.
    final pendingSession = context.watch<SessionProvider>().openSessionRequest;
    if (pendingSession != null && isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SessionProvider>().consumeOpenSession();
        _openOverlay(() => _activeSession = pendingSession);
      });
    }

    final pendingResults = context.watch<SessionProvider>().endedResults;
    if (pendingResults != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SessionProvider>().consumeEndedResults();
        if (_sessionResults != null) return;
        _openOverlay(() => _sessionResults = pendingResults);
      });
    }
    final tabs = [
      _buildHomeTab(),
      _buildMusicTab(),
      FriendsScreen(
        embedded: true,
        onFindFriends: isDesktop
            ? () => _openOverlay(() => _activeFriendView = 'search')
            : null,
        onOpenProfile: isDesktop
            ? (args) => _openOverlay(() => _viewingProfile = args)
            : null,
      ),
    ];
    void selectTab(int index) => setState(() {
          _clearOverlays();
          _currentIndex = index;
        });

    return Scaffold(
      backgroundColor: isDesktop
          ? context.colors.surfaceContainerLowest
          : context.colors.surface,
      body: isDesktop
          ? Padding(
              padding: EdgeInsets.all(layout.gutter),
              child: Row(children: [
              HomeNavigationRail(
                currentIndex: _currentIndex,
                onSelected: selectTab,
                maxWidth: layout.railMaxWidth,
                showLabels: layout.railLabels,
                unreadFriendRequests: unreadCount,
                onCreateSession: () =>
                    _openOverlay(() => _creatingSession = true),
                onFindFriends: () =>
                    _openOverlay(() => _activeFriendView = 'search'),
                onOpenLiked: () => selectTab(1),
                // Встроенно, а не маршрутом: полноэкранный переход закрыл
                // бы боковую панель и панель воспроизведения.
                onOpenHistory: () =>
                    _openOverlay(() => _showingHistory = true),
              ),

              // Зазор до центральной панели даёт сама область захвата
              // ширины внутри рельса — второй отступ здесь удвоил бы его.
              Expanded(
                  child: Row(children: [
                Expanded(
                    child: _Panel(
                        child: Column(children: [
                  if (!_hasOverlay) _buildDesktopHeader(),
                  Expanded(
                    child: _activeFriendView != null // ← новая проверка
                        ? (_activeFriendView == 'search'
                            ? SearchUsersScreen(
                                embedded: true,
                                onBack: () =>
                                    setState(() => _activeFriendView = null))
                            : FriendRequestsScreen(
                                embedded: true,
                                onBack: () =>
                                    setState(() => _activeFriendView = null)))
                        : _showingHistory
                            ? PlayHistoryScreen(
                                embedded: true,
                                onBack: () =>
                                    setState(() => _showingHistory = false),
                              )
                        : _showingSettings
                            ? SettingsScreen(
                                embedded: true,
                                onOpenHistory: () => _openOverlay(
                                    () => _showingHistory = true),
                                onBack: () =>
                                    setState(() => _showingSettings = false),
                              )
                        : _showingOwnProfile
                            ? ProfileScreen(
                                embedded: true,
                                onOpenHistory: () => _openOverlay(
                                    () => _showingHistory = true),
                                onOpenSettings: () => _openOverlay(
                                    () => _showingSettings = true),
                                onBack: () => setState(
                                    () => _showingOwnProfile = false),
                              )
                        : _viewingProfile != null
                            ? ProfileScreen(
                                embedded: true,
                                overrideArgs: _viewingProfile,
                                onBack: () =>
                                    setState(() => _viewingProfile = null),
                              )
                        : _showingInvites
                            ? SessionInvitesScreen(
                                embedded: true,
                                onBack: () =>
                                    setState(() => _showingInvites = false),
                              )
                        : _sessionResults != null
                            ? SessionResultsScreen(
                                embedded: true,
                                mutualLikes: (_sessionResults!['mutualLikes']
                                        as List?)
                                    ?.whereType<Map>()
                                    .toList(),
                                onClose: () =>
                                    setState(() => _sessionResults = null),
                              )
                            : _activeSession != null
                            ? SessionScreen(
                                embedded: true,
                                sessionData: _activeSession!,
                                onSessionEnded: (results) {
                                  setState(() {
                                    _activeSession = null;
                                    _sessionResults = results;
                                  });

                                  context
                                      .read<SessionProvider>()
                                      .fetchMySessions()
                                      .ignore();
                                },
                                onBack: () =>
                                    setState(() => _activeSession = null))
                            : _creatingSession
                                ? CreateSessionScreen(
                                    embedded: true,
                                    onCancel: () => setState(
                                        () => _creatingSession = false),
                                    onFindFriends: () => _openOverlay(
                                        () => _activeFriendView = 'search'),
                                    onSessionCreated: (session) =>
                                        setState(() {
                                          _creatingSession = false;
                                          _activeSession = session;
                                        }))
                                : _selectedPlaylist != null
                                    ? PlaylistTracksScreen(
                                        key: ValueKey(
                                            _selectedPlaylist!['id']),
                                        playlistId:
                                            _selectedPlaylist!['id'] ?? '',
                                        playlistName:
                                            _selectedPlaylist!['name'] ?? '',
                                        imageUrl:
                                            _selectedPlaylist!['imageUrl'],
                                        isCustom:
                                            _selectedPlaylist!['isCustom'] ??
                                                false,
                                        embedded: true,
                                        onDeleted: () => setState(
                                            () => _selectedPlaylist = null))
                                    : Center(
                                        child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                                maxWidth:
                                                    layout.contentMaxWidth),
                                            child: IndexedStack(
                                              key: _tabsKey,
                                              index: _currentIndex,
                                              children: tabs,
                                            ))),
                  ),
                ]))),

                if (layout.showNowPlayingPanel) ...[
                  SizedBox(width: layout.gutter),
                  SizedBox(
                      width: layout.sidePanelWidth,
                      child: _Panel(child: _buildRightPanel())),
                ],
              ])),
            ]))
          : SafeArea(
              child: Column(
                children: [
                  _MobileHeader(
                    title: homeDestinations(context)[_currentIndex].label,
                    onProfile: () =>
                        Navigator.of(context).pushNamed('/profile'),
                  ),
                  Expanded(child: _tabsStack(tabs)),
                ],
              ),
            ),
      bottomNavigationBar: isDesktop
          ? (layout.showNowPlayingPanel ? null : const MiniPlayerDock())
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                HomeBottomNav(
                  currentIndex: _currentIndex,
                  onSelected: selectTab,
                  unreadFriendRequests: unreadCount,
                ),
              ],
            ),
    );
  }

  Widget _tabsStack(List<Widget> tabs) {
    return IndexedStack(key: _tabsKey, index: _currentIndex, children: tabs);
  }
}

/// Шапка мобильной раскладки: название раздела и аватар профиля.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.title, required this.onProfile});

  final String title;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: context.texts.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onProfile,
            tooltip: L.of(context).accountProfile,
            icon: TappableAvatar(
              imageUrl: user?.effectiveAvatarUrl,
              radius: 16,
              title: user?.displayName,
              // Открытие профиля важнее просмотра аватара: нажатие должно
              // вести в профиль, а не разворачивать картинку.
              onTapOverride: onProfile,
            ),
          ),
        ],
      ),
    );
  }
}


class _CreatePlaylistTile extends StatelessWidget {
  const _CreatePlaylistTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: AppRadius.small,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.add_rounded, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(L.of(context).homeCreatePlaylist, style: context.texts.titleSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Приветственная карточка с двумя основными действиями.
class _StartSessionCard extends StatelessWidget {
  const _StartSessionCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Знак состояния сессии. Здесь он в покое: карточка показывается
          // ровно тогда, когда активной сессии нет.
          const Center(child: SyncMark(state: SyncPhase.idle)),
          const SizedBox(height: AppSpacing.md),
          Text(
            L.of(context).homeListenTogether,
            textAlign: TextAlign.center,
            style: texts.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            L.of(context).homeListenTogetherHint,
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add_rounded),
              label: Text(L.of(context).homeStartSession),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок раздела с необязательным счётчиком и действием справа.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.badgeCount});

  final String title;
  final Widget? action;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm + 4),
      child: Row(
        children: [
          Text(title, style: texts.titleLarge),
          if (badgeCount != null && badgeCount! > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '$badgeCount',
                style: texts.labelMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Строка списка на главном экране: приглашение или активная сессия.
class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: AppRadius.large,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: highlighted ? colors.primaryContainer : colors.surfaceContainerHighest,
                  borderRadius: AppRadius.small,
                ),
                child: Icon(
                  icon,
                  color: highlighted ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: texts.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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



/// Единая оболочка шапки широкой раскладки.
class _DesktopHeaderShell extends StatelessWidget {
  const _DesktopHeaderShell({
    required this.title,
    this.onBack,
    this.actions = const [],
    this.titleKey,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            AppIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: onBack,
              tooltip: L.of(context).commonBack,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              child: Text(
                title,
                key: titleKey ?? ValueKey(title),
                style: context.texts.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.large,
      ),
      child: child,
    );
  }
}