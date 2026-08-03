import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
import 'package:syncm/screens/settings/settings_screen.dart';
import 'package:syncm/screens/session/create_session_screen.dart';
import 'package:syncm/screens/session/session_screen.dart';
import 'package:syncm/screens/friends/search_users_screen.dart';
import 'package:syncm/screens/friends/friend_requests_screen.dart';
import 'package:syncm/services/prefetch_service.dart';
import 'package:syncm/services/socket_service.dart';
import '../../services/api_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/scrollable_playlist_row.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/interactive_card.dart';
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
import '../profile/profile_screen.dart';

// ---------- HomeScreen ----------

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

  /// Сбрасывает ВСЕ наложенные экраны широкой раскладки.
  ///
  /// Раньше эти состояния были независимы и могли быть подняты одновременно,
  /// а что показать — решал фиксированный порядок проверок. Отсюда три
  /// разных проявления одной ошибки:
  ///   • переключение вкладок в боковой панели не работало, пока открыто
  ///     создание сессии: selectTab сбрасывал остальные состояния, но не
  ///     _creatingSession, и наложенный экран продолжал перекрывать вкладку;
  ///   • «Найти друзей» поверх открытого создания сессии показывал друзей,
  ///     а создание сессии оставалось «под ним» и всплывало при закрытии;
  ///   • обратный порядок вовсе не срабатывал, потому что проверка друзей
  ///     стоит выше по списку.
  ///
  /// Теперь любой переход сначала гасит всё, и одновременно поднятых
  /// состояний просто не бывает.
  void _clearOverlays() {
    _creatingSession = false;
    _activeFriendView = null;
    _activeSession = null;
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

      // Прогрев всех разделов сразу, а не по мере открытия вкладок.
      //
      // Вместе с IndexedStack это и даёт ощущение мгновенности: к моменту,
      // когда человек переключится на «Друзья», список уже загружен, вкладка
      // построена и просто становится видимой.
      _prefetch.warmUp(friends: friendsProv, sessions: sessionProv).then((_) {
        if (mounted) _prefetch.warmUpAvatars(context, friendsProv.friends);
      });
    });
  }

  Future<void> _openSession(String sessionId) async {
  try {
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    final sessions = await api.getMySessions();
    final session = (sessions).firstWhere(
      (s) => s['id'] == sessionId,
      orElse: () => null,
    );
    if (session != null && mounted) {
      _openOverlay(() => _activeSession = Map<String, dynamic>.from(session));
    }
  } catch (e) {
    // showError вместо текста исключения: пользователю показывались
    // служебные строки вида «ApiException: ... (500) [Prisma...]».
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
      // showError сам молчит про 429 и внутренние сбои, поэтому проверку
      // suppressUiNotification повторять здесь не нужно.
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }
    try {
      final spotify = await api.getPlaylists();
      if (mounted) setState(() => _spotifyPlaylists = spotify);
    } catch (e) {
      // Отсутствие подключения к Spotify — не ошибка: раздел просто
      // покажет предложение подключить аккаунт, ругаться на это незачем.
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

    final child = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _WelcomeCard(
          onCreateSession: () {
            if (isDesktop) {
              _openOverlay(() => _creatingSession = true);
            } else {
              Navigator.of(context).pushNamed('/session/create');
            }
          },
          onFindFriends: () {
            if (isDesktop) {
              _openOverlay(() => _activeFriendView = 'search');
            } else {
              Navigator.of(context).pushNamed('/friends/search');
            }
          },
        ),

        _SectionHeader(
          title: 'Плейлисты',
          action: AppIconButton(
            icon: Icons.add_box_outlined,
            onPressed: _createCustomPlaylist,
            tooltip: 'Создать плейлист',
          ),
        ),
        SizedBox(
          // Высота считается от ширины карточки: обложка квадратная, плюс
          // место под две строки подписи. Раньше стояло жёсткое 220 —
          // при крупном системном шрифте подпись не помещалась.
          height: 208,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  // Цвета и индикатор берутся из темы, а не задаются здесь:
                  // раньше они дублировали значения из ThemeData и при смене
                  // палитры расходились с остальным интерфейсом.
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
          ),
        ),

        Consumer<SessionProvider>(
          builder: (context, prov, _) {
            // Раздел приглашений скрыт, когда их нет.
            //
            // Раньше он всегда занимал место с надписью «Нет входящих
            // приглашений» — постоянное напоминание о пустоте, которое к
            // тому же отодвигало вниз активные сессии, то есть то, ради чего
            // на экран обычно и заходят.
            if (prov.invites.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Приглашения',
                  badgeCount: prov.invites.length,
                  action: TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/session/invites'),
                    child: const Text('Все'),
                  ),
                ),
                ...prov.invites.take(3).map((invite) {
                  final hostName = prov.hostNameForInvite(invite) ?? 'Друг';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _HomeTile(
                      icon: Icons.mail_outline_rounded,
                      title: invite['name'] as String? ?? 'Сессия',
                      subtitle: 'Приглашение от $hostName',
                      onTap: () => Navigator.of(context).pushNamed('/session/invites'),
                    ),
                  );
                }),
              ],
            );
          },
        ),

        Consumer<SessionProvider>(
          builder: (context, prov, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Активные сессии',
                  action: TextButton(
                    onPressed: prov.loading ? null : prov.fetchMySessions,
                    child: const Text('Обновить'),
                  ),
                ),
                if (prov.loading && prov.sessions.isEmpty)
                  // Скелетон вместо кружка: повторяет форму будущих строк,
                  // поэтому при подстановке данных разметка не «прыгает», а
                  // ожидание выглядит короче — экран уже наполнен.
                  const SkeletonList(
                    itemCount: 2,
                    avatarRadius: 22,
                    padding: EdgeInsets.zero,
                  )
                else if (prov.sessions.isEmpty)
                  _EmptySessionsCard(
                    onCreate: () {
                      if (isDesktop) {
                        _openOverlay(() => _creatingSession = true);
                      } else {
                        Navigator.of(context).pushNamed('/session/create');
                      }
                    },
                  )
                else
                  ...prov.sessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _HomeTile(
                        icon: Icons.headphones_rounded,
                        title: session.name,
                        // Раньше здесь показывался обрезок идентификатора
                        // («Host: 3f9a2c») — служебные данные, которые
                        // пользователю ничего не говорят.
                        subtitle: 'Нажмите, чтобы открыть',
                        highlighted: true,
                        onTap: () => _openSession(session.id),
                      ),
                    ),
                  ),
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
          _loadAllPlaylists(),
          sessions.fetchMySessions(),
          sessions.fetchInvites(refresh: true),
        ]);
      },
      child: child,
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
            // tonal вместо elevated: это подсказка внутри раздела, а не
            // главное действие экрана, и залитая кнопка перетягивала бы
            // внимание с приветственной карточки выше.
            FilledButton.tonalIcon(
              icon: Icon(isCustom ? Icons.add_rounded : Icons.link_rounded),
              label: Text(isCustom ? 'Создать' : 'Подключить Spotify'),
              onPressed: () => isCustom
                  ? _createCustomPlaylist()
                  : Navigator.of(context).pushNamed('/profile'),
            ),
          ],
        ),
      );
    }
    return ScrollablePlaylistRow(
        itemCount: playlists.length,
        itemBuilder: (_, i) {
          final p = playlists[i];
          return PlaylistCard(
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
              // Форма, цвета и шрифты берутся из dialogTheme.
              //
              // Раньше здесь вручную задавались радиус 24, радиусы рамок
              // поля, цвета границ в трёх состояниях и цвета кнопки — всё
              // это дублировало значения из темы и при смене палитры
              // расходилось с остальным интерфейсом.
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
                  // Отключённое состояние оформляет сама тема: прежний код
                  // вручную подбирал цвета фона и текста для неактивной
                  // кнопки, и они не совпадали с остальными кнопками.
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
          // Заголовок «Панель» убран: слово ничего не сообщает, а место
          // занимало. Содержимое и так говорит само за себя.
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

    const tabTitles = ['Главная', 'Друзья', 'Профиль', 'Настройки'];

    return _DesktopHeaderShell(
      title: _selectedPlaylist != null
          ? _selectedPlaylist!['name'] as String? ?? 'Плейлист'
          : tabTitles[_currentIndex.clamp(0, tabTitles.length - 1)],
      titleKey: ValueKey(_selectedPlaylist?['id'] ?? _currentIndex),
      onBack: _selectedPlaylist != null
          ? () => setState(() => _selectedPlaylist = null)
          : null,
      actions: [
        if (_currentIndex == 1) ...[
          AppIconButton(
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => _openOverlay(() => _activeFriendView = 'search'),
            tooltip: 'Поиск друзей',
          ),
          // Счётчик заявок с той же анимацией, что и на узком экране:
          // раньше здесь была обычная иконка без числа, и о новых заявках
          // на десктопе узнать было неоткуда.
          Consumer<FriendsProvider>(
            builder: (context, prov, _) => AnimatedNotificationButton(
              icon: Icons.mail_outline_rounded,
              activeIcon: Icons.mark_email_unread_rounded,
              count: prov.unreadCount,
              tooltip: 'Заявки в друзья',
              onPressed: () => _openOverlay(() => _activeFriendView = 'requests'),
            ),
          ),
        ] else if (_currentIndex == 0)
          AppIconButton(
            icon: Icons.add_rounded,
            onPressed: () => _openOverlay(() => _creatingSession = true),
            tooltip: 'Создать сессию',
          ),
        AppIconButton(
          icon: themeProvider.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          onPressed: themeProvider.toggleTheme,
          tooltip: themeProvider.isDark ? 'Светлая тема' : 'Тёмная тема',
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 900;
      if (!isDesktop && _currentIndex > 2) _currentIndex = 0;
      final unreadCount = Provider.of<FriendsProvider>(context).unreadCount;
      final tabsMobile = [
        _buildHomeTab(),
        FriendsScreen(embedded: true),
        ProfileScreen(embedded: true)
      ];
      final tabsDesktop = [
        _buildHomeTab(),
        // onFindFriends: в широкой раскладке поиск открывается встроенным
        // блоком, сохраняя боковую панель и панель воспроизведения. Без
        // этого кнопка в пустом списке друзей открывала поиск отдельным
        // маршрутом на весь экран — то есть вела себя иначе, чем такая же
        // кнопка в шапке.
        FriendsScreen(
          embedded: true,
          onFindFriends: () => _openOverlay(() => _activeFriendView = 'search'),
        ),
        ProfileScreen(embedded: true),
        const SettingsScreen(embedded: true)
      ];
      // Смена вкладки гасит все наложенные экраны, включая создание сессии:
      // без этого нажатие на вкладку в боковой панели визуально ничего не
      // делало, а переход происходил только после закрытия наложенного окна.
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
                    _buildDesktopHeader(),
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
                          : _activeSession != null
                              ? SessionScreen(
                                  embedded: true,
                                  sessionData: _activeSession!,
                                  onBack: () =>
                                      setState(() => _activeSession = null))
                              : _creatingSession
                                  ? CreateSessionScreen(
                                      embedded: true,
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
                                                children: tabsDesktop,
                                              ))),
                    ),
                  ])),
                  SizedBox(width: 320, child: _buildRightPanel()),
                ])),
              ])
            : SafeArea(
                // IndexedStack вместо AnimatedSwitcher.
                //
                // Переключение вкладок теперь мгновенное и без затухания.
                // Прежний вариант проигрывал 280 мс перекрёстного
                // растворения: на стыке оба экрана были полупрозрачными, и
                // переход читался как задержка, хотя данные уже готовы.
                //
                // Важнее другое: AnimatedSwitcher уничтожал старую вкладку и
                // строил новую с нуля. Позиция прокрутки, введённый текст,
                // раскрытые списки — всё терялось, а провайдеры заново
                // запрашивали данные. IndexedStack держит все вкладки
                // построенными и лишь меняет видимую, поэтому возврат на
                // вкладку возвращает её ровно в том виде, в каком её
                // оставили.
                child: IndexedStack(
                  index: _currentIndex,
                  children: tabsMobile,
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
}


/// Приветственная карточка с двумя основными действиями.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onCreateSession, required this.onFindFriends});

  final VoidCallback onCreateSession;
  final VoidCallback onFindFriends;

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
          Text('Добро пожаловать', style: texts.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Создайте сессию и слушайте музыку одновременно с друзьями — '
            'где бы вы ни были.',
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Кнопки в столбец, а не Wrap: в строке они делились пополам и на
          // узком экране подписи обрезались, а порядок «главное — сначала»
          // терялся при переносе.
          FilledButton.icon(
            onPressed: onCreateSession,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новая сессия'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onFindFriends,
            icon: const Icon(Icons.person_search_rounded),
            label: const Text('Найти друзей'),
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

class _EmptySessionsCard extends StatelessWidget {
  const _EmptySessionsCard({required this.onCreate});

  final VoidCallback onCreate;

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
        children: [
          Icon(Icons.headphones_outlined, size: 44, color: colors.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm + 4),
          Text('Пока нет сессий', style: texts.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Создайте сессию и пригласите друга — музыка будет играть у вас одновременно.',
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Создать сессию'),
          ),
        ],
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
        // Граница из палитры вместо dividerColor с прозрачностью 6%: та
        // была почти невидима на тёмной теме, и шапка сливалась с контентом.
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