import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
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
import '../../services/api_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable_avatar.dart';
import '../../widgets/app_icon_button.dart';
import '../../theme.dart';
import '../../widgets/animated_notification_button.dart';
import '../../utils/error_utils.dart';
import '../../widgets/home_nav.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/now_playing_panel.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/friends_provider.dart';
import '../friends/friends_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<dynamic> _customPlaylists = [];
  List<dynamic> _spotifyPlaylists = [];
  bool _loadingCustom = false;
  bool _loadingSpotify = false;
  Map<String, dynamic>? _selectedPlaylist;
  final _prefetch = PrefetchService();



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
    _selectedPlaylist = null;
  }

  void _openOverlay(VoidCallback apply) {
    setState(() {
      _clearOverlays();
      apply();
    });
  }
  Map<String, dynamic>? _activeSession;

  Map<String, dynamic>? _sessionResults;

  bool _showingInvites = false;

  Map<String, dynamic>? _viewingProfile;

  bool _showingOwnProfile = false;
  bool _showingSettings = false;
  String? _activeFriendView; // 'search' или 'requests'


  @override
  void initState() {
    super.initState();
    _loadAllPlaylists();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final socket = SocketService();
      final friendsProv = context.read<FriendsProvider>();
      final sessionProv = context.read<SessionProvider>();

      friendsProv.init(socket);
      sessionProv.init(socket);

      _prefetch.warmUp(friends: friendsProv, sessions: sessionProv).then((_) {
        if (mounted) _prefetch.warmUpAvatars(context, friendsProv.friends);
      });
    });
  }

  bool get _hasOverlay =>
      _showingSettings ||
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

    if (MediaQuery.sizeOf(context).width < 900) {
      await Navigator.of(context).pushNamed('/session', arguments: data);
      return;
    }

    _openOverlay(() => _activeSession = data);
  } catch (e) {
    if (mounted) showError(context, e);
  }
}

  Future<void> _loadAllPlaylists() async {
    if (mounted) {
      setState(() {
        _loadingCustom = true;
        _loadingSpotify = true;
      });
    }
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    try {
      final custom = await api.getMyPlaylists();
      if (mounted) setState(() => _customPlaylists = custom);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }
    try {
      final spotify = await api.getPlaylists();
      if (mounted) setState(() => _spotifyPlaylists = spotify);
    } catch (e) {
      final notConnected = e is ApiException && e.statusCode == 409;
      if (mounted && !notConnected) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingSpotify = false);
    }
  }

  Widget _buildHomeTab() {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
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
                if (invites.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Вас зовут',
                    badgeCount: invites.length,
                    action: TextButton(
                      onPressed: () => _openInvites(isDesktop),
                      child: const Text('Все'),
                    ),
                  ),
                  ...invites.take(2).map((invite) {
                    final hostName = prov.hostNameForInvite(invite) ?? 'Друг';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _HomeTile(
                        icon: Icons.mail_outline_rounded,
                        title: invite['name'] as String? ?? 'Сессия',
                        subtitle: 'От $hostName',
                        onTap: () => _openInvites(isDesktop),
                      ),
                    );
                  }),
                ],

                if (prov.loading && sessions.isEmpty)
                  const SkeletonList(itemCount: 1, avatarRadius: 22, padding: EdgeInsets.zero)
                else if (sessions.isEmpty)
                  _StartSessionCard(onStart: startSession)
                else ...[
                  _SectionHeader(
                    title: 'Сейчас слушаете',
                    action: TextButton(
                      onPressed: prov.loading ? null : prov.fetchMySessions,
                      child: const Text('Обновить'),
                    ),
                  ),
                  ...sessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _HomeTile(
                        icon: Icons.graphic_eq_rounded,
                        title: session.name,
                        subtitle: 'Нажмите, чтобы открыть',
                        highlighted: true,
                        onTap: () => _openSession(session.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: startSession,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ещё одна сессия'),
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
          sessions.fetchInvites(refresh: true),
        ]);
      },
      child: child,
    );
  }

  Widget _buildMusicTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Мои'), Tab(text: 'Spotify')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPlaylistsTab(true),
                _buildPlaylistsTab(false),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPlaylistsTab(bool isCustom) {
    final playlists = isCustom ? _customPlaylists : _spotifyPlaylists;
    final loading = isCustom ? _loadingCustom : _loadingSpotify;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    if (loading) return const SkeletonPlaylistRow();
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCustom ? Icons.playlist_add_rounded : Icons.link_rounded,
              size: 36,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isCustom ? 'Своих плейлистов пока нет' : 'Плейлисты Spotify недоступны',
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            FilledButton.tonalIcon(
              icon: Icon(isCustom ? Icons.add_rounded : Icons.link_rounded),
              label: Text(isCustom ? 'Создать' : 'Подключить Spotify'),
              onPressed: () => isCustom
                  ? _createCustomPlaylist()
                  : _openOwnProfile(isDesktop),
            ),
          ],
        ),
      );
    }
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
          final p = playlists[i];
          return PlaylistCard(
            dense: true,
            name: p['name'] ?? '',
            description: p['description'] ?? '',
            imageUrl: p['imageUrl'],
            onTap: () {
              if (isDesktop) {
                setState(() {
                  _selectedPlaylist = {
                    'id': p['id'],
                    'name': p['name'],
                    'imageUrl': p['imageUrl'],
                    'isCustom': isCustom
                  };
                });
              } else {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlaylistTracksScreen(
                        playlistId: p['id'] ?? '',
                        playlistName: p['name'] ?? '',
                        imageUrl: p['imageUrl'],
                        isCustom: isCustom)));
              }
            },
          );
        });
  }

  Future<void> _createCustomPlaylist() async {
    final nameController = TextEditingController();
    String? nameError;
    bool valid = false;

    void validate(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        nameError = 'Название не может быть пустым';
        valid = false;
      } else if (trimmed.length < 2) {
        nameError = 'Минимум 2 символа';
        valid = false;
      } else if (trimmed.length > 50) {
        nameError = 'Не более 50 символов';
        valid = false;
      } else if (!RegExp(r'^[а-яА-ЯёЁa-zA-Z0-9 ._\-()]+$').hasMatch(trimmed)) {
        nameError = 'Только буквы, цифры, пробелы и ._-()';
        valid = false;
      } else {
        nameError = null;
        valid = true;
      }
    }

    validate(nameController.text);

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              icon: const Icon(Icons.playlist_add_rounded),
              title: const Text('Новый плейлист'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 50,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[а-яА-ЯёЁa-zA-Z0-9 ._\-()]'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Название',
                  counterText: '',
                  errorText: nameError,
                ),
                onChanged: (value) {
                  validate(value);
                  setDialogState(() {});
                },
                onSubmitted: (value) {
                  if (valid) Navigator.of(ctx).pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: valid
                      ? () => Navigator.of(ctx).pop(nameController.text.trim())
                      : null,
                  child: const Text('Создать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      try {
        final api = Provider.of<AuthProvider>(context, listen: false).api;
        await api.createCustomPlaylist(name);
        await _loadAllPlaylists();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Widget _buildRightPanel() {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _openOverlay(() => _creatingSession = true),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новая сессия'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _openOverlay(() => _activeFriendView = 'search'),
            icon: const Icon(Icons.person_search_rounded),
            label: const Text('Найти друзей'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
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
                          'Ничего не играет',
                          style: texts.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Выберите трек из плейлиста — управление появится здесь.',
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

  Widget _buildDesktopHeader() {
    final auth = context.read<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    if (_activeFriendView != null) {
      return _DesktopHeaderShell(
        title: _activeFriendView == 'search' ? 'Поиск друзей' : 'Заявки в друзья',
        onBack: () => setState(() => _activeFriendView = null),
      );
    }

    if (_activeSession != null) {
      final isHost = _activeSession!['hostId'] == auth.user?.id;
      return _DesktopHeaderShell(
        title: _activeSession!['name'] as String? ?? 'Сессия',
        onBack: () => setState(() => _activeSession = null),
        actions: [
          if (isHost)
            TextButton.icon(
              onPressed: _endActiveSession,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Завершить'),
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
            ),
        ],
      );
    }

    if (_creatingSession) {
      return _DesktopHeaderShell(
        title: 'Новая сессия',
        onBack: () => setState(() => _creatingSession = false),
      );
    }

    final tabTitles = kHomeDestinations.map((d) => d.label).toList();

    return _DesktopHeaderShell(
      title: _selectedPlaylist != null
          ? _selectedPlaylist!['name'] as String? ?? 'Плейлист'
          : tabTitles[_currentIndex.clamp(0, tabTitles.length - 1)],
      titleKey: ValueKey(_selectedPlaylist?['id'] ?? _currentIndex),
      onBack: _selectedPlaylist != null
          ? () => setState(() => _selectedPlaylist = null)
          : null,
      actions: [
        if (_currentIndex == 2) ...[
          AppIconButton(
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => _openOverlay(() => _activeFriendView = 'search'),
            tooltip: 'Поиск друзей',
          ),
          Consumer<FriendsProvider>(
            builder: (context, prov, _) => AnimatedNotificationButton(
              icon: Icons.mail_outline_rounded,
              activeIcon: Icons.mark_email_unread_rounded,
              count: prov.unreadCount,
              tooltip: 'Заявки в друзья',
              onPressed: () => _openOverlay(() => _activeFriendView = 'requests'),
            ),
          ),
        ] else if (_currentIndex == 0) ...[
          AppIconButton(
            icon: Icons.refresh_rounded,
            onPressed: () {
              final sessions = context.read<SessionProvider>();
              sessions.fetchMySessions();
              sessions.fetchInvites(refresh: true);
            },
            tooltip: 'Обновить',
          ),
          AppIconButton(
            icon: Icons.add_rounded,
            onPressed: () => _openOverlay(() => _creatingSession = true),
            tooltip: 'Создать сессию',
          ),
        ],
        AppIconButton(
          icon: themeProvider.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          onPressed: themeProvider.toggleTheme,
          tooltip: themeProvider.isDark ? 'Светлая тема' : 'Тёмная тема',
        ),

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
      showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 900;
      // Вкладок теперь три в обеих раскладках — подрезать индекс не нужно.
      final unreadCount = Provider.of<FriendsProvider>(context).unreadCount;

      final pendingSession = context.watch<SessionProvider>().openSessionRequest;
      if (pendingSession != null && isDesktop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<SessionProvider>().consumeOpenSession();
          _openOverlay(() => _activeSession = pendingSession);
        });
      }

      final pendingResults = context.watch<SessionProvider>().endedResults;
      if (pendingResults != null && _sessionResults == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<SessionProvider>().consumeEndedResults();
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
        body: isDesktop
            ? Row(children: [
                HomeNavigationRail(
                  currentIndex: _currentIndex,
                  onSelected: selectTab,
                  onToggleTheme: themeProvider.toggleTheme,
                  isDark: themeProvider.isDark,
                  unreadFriendRequests: unreadCount,
                ),

                const VerticalDivider(width: 1),
                Expanded(
                    child: Row(children: [
                  Expanded(
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
                          : _showingSettings
                              ? SettingsScreen(
                                  embedded: true,
                                  onBack: () =>
                                      setState(() => _showingSettings = false),
                                )
                          : _showingOwnProfile
                              ? ProfileScreen(
                                  embedded: true,
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
                                      onSessionCreated: (session) =>
                                          setState(() {
                                            _creatingSession = false;
                                            _activeSession = session;
                                          }))
                                  : _selectedPlaylist != null
                                      ? PlaylistTracksScreen(
                                          playlistId:
                                              _selectedPlaylist!['id'] ?? '',
                                          playlistName:
                                              _selectedPlaylist!['name'] ?? '',
                                          imageUrl:
                                              _selectedPlaylist!['imageUrl'],
                                          isCustom:
                                              _selectedPlaylist!['isCustom'] ??
                                                  false,
                                          embedded: true)
                                      : Center(
                                          child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 1100),
                                              child: IndexedStack(
                                                index: _currentIndex,
                                                children: tabs,
                                              ))),
                    ),
                  ])),
                  SizedBox(width: 320, child: _buildRightPanel()),
                ])),
              ])
            : SafeArea(
                child: Column(
                  children: [
                    _MobileHeader(
                      title: kHomeDestinations[_currentIndex].label,
                      onProfile: () =>
                          Navigator.of(context).pushNamed('/profile'),
                    ),
                    Expanded(child: _tabsStack(tabs)),
                  ],
                ),
              ),
        bottomNavigationBar: isDesktop
            ? null
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
    });
  }

  Widget _tabsStack(List<Widget> tabs) {
    return IndexedStack(index: _currentIndex, children: tabs);
  }
}

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
            tooltip: 'Профиль',
            icon: TappableAvatar(
              imageUrl: user?.effectiveAvatarUrl,
              radius: 16,
              title: user?.displayName,
              onTapOverride: onProfile,
            ),
          ),
        ],
      ),
    );
  }
}


class _StartSessionCard extends StatelessWidget {
  const _StartSessionCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final roles = context.roles;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(-16, 0),
                  child: _Dot(color: roles.mine),
                ),
                Transform.translate(
                  offset: const Offset(16, 0),
                  child: _Dot(color: roles.theirs),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Слушайте вместе',
            textAlign: TextAlign.center,
            style: texts.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Позовите друга — музыка пойдёт у вас одновременно, '
            'где бы вы ни были.',
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Начать сессию'),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.9),
      ),
    );
  }
}

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
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
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
              tooltip: 'Назад',
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