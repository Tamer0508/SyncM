import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/settings/settings_screen.dart';
import 'package:syncm/services/socket_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/scrollable_playlist_row.dart';
import '../../widgets/interactive_card.dart';
import '../../widgets/mini_player.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/friends_provider.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../playlist/playlist_tracks_screen.dart';
import '../../utils/notifications.dart';
  
class _RailIconWidget extends StatefulWidget {
  final IconData icon;
  final bool selected;

  const _RailIconWidget({Key? key, required this.icon, required this.selected}) : super(key: key);

  @override
  State<_RailIconWidget> createState() => _RailIconWidgetState();
}

class _RailIconWidgetState extends State<_RailIconWidget> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final bgColor = widget.selected ? primary : (_hover ? primary.withOpacity(0.12) : Colors.transparent);
    final iconColor = widget.selected ? Colors.white : theme.iconTheme.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: widget.selected
              ? [BoxShadow(color: primary.withOpacity(0.16), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Icon(widget.icon, color: iconColor, size: 22),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _railExpanded = false;

  List<dynamic> _customPlaylists = [];
  List<dynamic> _spotifyPlaylists = [];
  bool _loadingCustom = false;
  bool _loadingSpotify = false;

  @override
  void initState() {
    super.initState();
    _loadAllPlaylists();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.user?.id;
    if (userId != null) {
      final socket = SocketService();
      socket.init(auth.api.baseUrl, userId);
      Provider.of<FriendsProvider>(context, listen: false).listenToSocket();
    }
  }

  Future<void> _loadAllPlaylists() async {
    if (mounted) setState(() {
      _loadingCustom = true;
      _loadingSpotify = true;
    });
    final api = Provider.of<AuthProvider>(context, listen: false).api;

    try {
      final custom = await api.getMyPlaylists();
      if (mounted) setState(() => _customPlaylists = custom);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, message: 'Ошибка загрузки своих плейлистов: $e', type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }

    try {
      final spotify = await api.getPlaylists();
      if (mounted) setState(() => _spotifyPlaylists = spotify);
    } catch (e) {
      if (mounted && e.toString().contains('Spotify не подключен') == false) {
        showAppNotification(context, message: 'Ошибка загрузки Spotify плейлистов: $e', type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _loadingSpotify = false);
    }
  }

  Widget _buildHomeTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InteractiveCard(
          margin: EdgeInsets.zero,
          borderRadius: 26,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Добро пожаловать в SyncM',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                'Обновлённый интерфейс для музыки и общения. Найдите друзей, создайте сессии и синхронизируйте любимый звук.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.78), height: 1.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Новая сессия'),
                    onPressed: () => Navigator.of(context).pushNamed('/session/create'),
                    style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text('Поиск друзей'),
                    onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                    style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Плейлисты',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _createCustomPlaylist,
              tooltip: 'Создать плейлист',
            ),
          ],
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 220,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(text: 'Мои'),
                    Tab(text: 'Spotify'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildCustomPlaylistsTab(),
                      _buildSpotifyPlaylistsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Активные сессии',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () async {
                await Provider.of<SessionProvider>(context, listen: false).fetchMySessions();
              },
              child: const Text('Обновить'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Consumer<SessionProvider>(builder: (_, prov, __) {
          if (prov.loading) {
            return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
          }
          if (prov.sessions.isEmpty) {
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                child: Column(
                  children: [
                    Text('Нет активных сессий',
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Создайте сессию и пригласите друзей, чтобы начать совместное прослушивание.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.78)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: prov.sessions
                .map((s) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        tileColor: theme.cardColor,
                        title: Text(s.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text('Host: ${s.id.substring(0, 6)}',
                            style: theme.textTheme.bodySmall),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pushNamed('/session'),
                      ),
                    ))
                .toList(),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCustomPlaylistsTab() {
    if (_loadingCustom) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Нет своих плейлистов', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Создать плейлист'),
              onPressed: () => _createCustomPlaylist(),
            ),
          ],
        ),
      );
    }
    return ScrollablePlaylistRow(
      itemCount: _customPlaylists.length,
      itemBuilder: (_, i) {
        final p = _customPlaylists[i];
        return PlaylistCard(
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          imageUrl: p['imageUrl'],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistTracksScreen(
              playlistId: p['id'] ?? '',
              playlistName: p['name'] ?? '',
              imageUrl: p['imageUrl'],
              isCustom: true,
            ),
          )),
        );
      },
    );
  }

  Widget _buildSpotifyPlaylistsTab() {
    if (_loadingSpotify) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_spotifyPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Нет Spotify плейлистов', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Подключить Spotify'),
              onPressed: () => Navigator.of(context).pushNamed('/profile'),
            ),
          ],
        ),
      );
    }
    return ScrollablePlaylistRow(
      itemCount: _spotifyPlaylists.length,
      itemBuilder: (_, i) {
        final p = _spotifyPlaylists[i];
        return PlaylistCard(
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          imageUrl: p['imageUrl'],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistTracksScreen(
              playlistId: p['id'] ?? '',
              playlistName: p['name'] ?? '',
              imageUrl: p['imageUrl'],
              isCustom: false,
            ),
          )),
        );
      },
    );
  }

  Future<void> _createCustomPlaylist() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        final api = Provider.of<AuthProvider>(context, listen: false).api;
        await api.createCustomPlaylist(name);
        await _loadAllPlaylists();
      } catch (e) {
        if (mounted) {
          showAppNotification(context, message: 'Ошибка создания плейлиста: $e', type: NotificationType.error);
        }
      }
    }
  }

  Widget _buildRightPanel() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Панель',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          InteractiveCard(
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Быстрые действия',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Новая сессия'),
                  onPressed: () => Navigator.of(context).pushNamed('/session/create'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_search),
                  label: const Text('Найти друзей'),
                  onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Consumer<PlaybackProvider>(builder: (_, pb, __) {
            if (pb.currentTrack == null) {
              return InteractiveCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Сейчас играет',
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Плейлист пуст', style: theme.textTheme.bodyMedium),
                  ],
                ),
              );
            }
            final t = pb.currentTrack!;
            return InteractiveCard(
              borderRadius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сейчас играет',
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(t['title'] ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(t['artist'] ?? '', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(
                              pb.isPlaying ? Icons.pause : Icons.play_arrow),
                          label: Text(pb.isPlaying ? 'Пауза' : 'Воспроизвести'),
                          onPressed: () => pb.togglePlay(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Icon(Icons.queue_music),
                      ),
                    ],
                  )
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Expanded(child: Container()),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader() {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                ['Главная', 'Друзья', 'Профиль', 'Настройки'][_currentIndex],
                key: ValueKey(_currentIndex),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Row(
            children: [
              if (_currentIndex == 1) ...[
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () => Navigator.of(context).pushNamed('/friends/requests'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await Provider.of<FriendsProvider>(context, listen: false).fetchFriends();
                  },
                ),
              ] else if (_currentIndex == 0) ...[
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => Navigator.of(context).pushNamed('/session/create'),
                ),
              ],
              if (_currentIndex == 2) ...[
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).pushNamed('/settings'),
                ),
              ],
              IconButton(
                icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode),
                onPressed: () => themeProvider.toggleTheme(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        if (!isDesktop && _currentIndex > 2) {
          _currentIndex = 0;
        }

        final tabsMobile = [
          _buildHomeTab(),
          FriendsScreen(embedded: true),
          ProfileScreen(embedded: true),
        ];
        final tabsDesktop = [
          _buildHomeTab(),
          FriendsScreen(embedded: true),
          ProfileScreen(embedded: true),
          const SettingsScreen(),
        ];

        // MiniPlayer всегда присутствует в разметке, но показывается только если есть трек
        final miniPlayerWidget = const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: MiniPlayer(),
        );

        // Для мобильной версии: плеер + нижняя навигация
        final mobileBottomNav = !isDesktop
            ? SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    miniPlayerWidget,
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? CupertinoTabBar(
                            currentIndex: _currentIndex,
                            onTap: (i) => setState(() => _currentIndex = i),
                            activeColor: Theme.of(context).colorScheme.primary,
                            items: const [
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.home), label: 'Главная'),
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.people), label: 'Друзья'),
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.person), label: 'Профиль'),
                            ],
                          )
                        : BottomNavigationBar(
                            currentIndex: _currentIndex,
                            onTap: (i) => setState(() => _currentIndex = i),
                            items: const [
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.home), label: 'Главная'),
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.people), label: 'Друзья'),
                              BottomNavigationBarItem(
                                  icon: Icon(Icons.person), label: 'Профиль'),
                            ],
                          ),
                  ],
                ),
              )
            : null;

        return Scaffold(
          // body без SafeArea для десктопа
          body: isDesktop
              ? Row(
                  children: [
                    // NavigationRail
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _railExpanded ? 220 : 92,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _railExpanded = true),
                        onExit: (_) => setState(() => _railExpanded = false),
                        child: NavigationRail(
                          labelType: _railExpanded
                              ? NavigationRailLabelType.all
                              : NavigationRailLabelType.none,
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18.0),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('SyncM',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: Icon(themeProvider.isDark
                                    ? Icons.dark_mode
                                    : Icons.light_mode),
                                onPressed: () => themeProvider.toggleTheme(),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (i) =>
                              setState(() => _currentIndex = i),
                          destinations: [
                            NavigationRailDestination(
                              icon: _RailIconWidget(
                                  icon: Icons.home, selected: _currentIndex == 0),
                              selectedIcon: _RailIconWidget(
                                  icon: Icons.home, selected: _currentIndex == 0),
                              label: const Text('Главная'),
                            ),
                            NavigationRailDestination(
                              icon: _RailIconWidget(
                                  icon: Icons.people, selected: _currentIndex == 1),
                              selectedIcon: _RailIconWidget(
                                  icon: Icons.people, selected: _currentIndex == 1),
                              label: const Text('Друзья'),
                            ),
                            NavigationRailDestination(
                              icon: _RailIconWidget(
                                  icon: Icons.person, selected: _currentIndex == 2),
                              selectedIcon: _RailIconWidget(
                                  icon: Icons.person, selected: _currentIndex == 2),
                              label: const Text('Профиль'),
                            ),
                            NavigationRailDestination(
                              icon: _RailIconWidget(
                                  icon: Icons.settings, selected: _currentIndex == 3),
                              selectedIcon: _RailIconWidget(
                                  icon: Icons.settings, selected: _currentIndex == 3),
                              label: const Text('Настройки'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // Основная область с контентом и правой панелью
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildDesktopHeader(),
                                Expanded(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 1100),
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 280),
                                        child: KeyedSubtree(
                                          key: ValueKey(
                                              'desktop_$_currentIndex'),
                                          child: tabsDesktop[_currentIndex],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: _buildRightPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : SafeArea(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: KeyedSubtree(
                      key: ValueKey('mobile_$_currentIndex'),
                      child: tabsMobile[_currentIndex],
                    ),
                  ),
                ),
          // Плеер всегда внизу за пределами body
          bottomNavigationBar: isDesktop
              ? Consumer<PlaybackProvider>(
                  builder: (_, pb, __) =>
                      pb.currentTrack != null ? miniPlayerWidget : const SizedBox.shrink(),
                )
              : mobileBottomNav,
        );
      },
    );
  }
}