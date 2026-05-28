import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/settings/settings_screen.dart';
import 'package:syncm/services/socket_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/scrollable_playlist_row.dart';
import '../../widgets/interactive_card.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/friends_provider.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../playlist/playlist_tracks_screen.dart';

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
  List<dynamic> _playlists = [];
  bool _loadingPlaylists = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.user?.id;
      if (userId != null) {
        final socket = SocketService();
        socket.init(auth.api.baseUrl, userId);
        Provider.of<FriendsProvider>(context, listen: false).listenToSocket();
      }
  }

    Future<void> _loadPlaylists() async {
    if (mounted) setState(() => _loadingPlaylists = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final playlists = await api.getMyPlaylists(); 
      if (mounted) setState(() => _playlists = playlists);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки плейлистов: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPlaylists = false);
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
              Text('Добро пожаловать в SyncM', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                'Обновлённый интерфейс для музыки и общения. Найдите друзей, создайте сессии и синхронизируйте любимый звук.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78), height: 1.5),
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
                    style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text('Поиск друзей'),
                    onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Мои плейлисты',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 220, 
          child: _loadingPlaylists
              ? Center(
                  child: CircularProgressIndicator(
                      color: theme.colorScheme.primary))
              : _playlists.isEmpty
                  ? Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 24, horizontal: 18),
                          child: Text(
                              'Плейлисты ещё не загружены или их нет в вашей библиотеке.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.8)),
                              textAlign: TextAlign.center),
                        ),
                      ),
                    )
                  : DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: const [
                              Tab(text: 'Свои'),
                              Tab(text: 'Spotify'),
                              Tab(text: 'Другие'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildCustomPlaylistsTab(),
                                _buildSpotifyPlaylistsTab(),
                                _buildOtherPlaylistsTab(),
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
            Text('Активные сессии', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
                    Text('Нет активных сессий', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Создайте сессию и пригласите друзей, чтобы начать совместное прослушивание.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78)), textAlign: TextAlign.center),
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
                        title: Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text('Host: ${s.id.substring(0, 6)}', style: theme.textTheme.bodySmall),
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

  Widget _buildRightPanel() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Панель', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          InteractiveCard(
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Быстрые действия', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
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
                    Text('Сейчас играет', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
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
                  Text('Сейчас играет', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(t['title'] ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(t['artist'] ?? '', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(pb.isPlaying ? Icons.pause : Icons.play_arrow),
                        label: Text(pb.isPlaying ? 'Пауза' : 'Воспроизвести'),
                        onPressed: () => pb.togglePlay(),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Icon(Icons.queue_music),
                      ),
                    ],
                  ),
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

  Widget _buildCustomPlaylistsTab() {
    final custom = _playlists.where((p) => p['isCustom'] == true).toList();
    if (custom.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Нет своих плейлистов',
                style: Theme.of(context).textTheme.bodyMedium),
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
      itemCount: custom.length,
      itemBuilder: (_, i) {
        final p = custom[i];
        return PlaylistCard(
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          imageUrl: p['imageUrl'],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistTracksScreen(
              playlistId: p['id'] ?? '',
              playlistName: p['name'] ?? '',
              imageUrl: p['imageUrl'],
            ),
          )),
        );
      },
    );
  }

  Widget _buildSpotifyPlaylistsTab() {
    final spotify = _playlists.where((p) => p['spotifyId'] != null).toList();
    if (spotify.isEmpty) {
      return Center(
        child: Text('Нет Spotify-плейлистов',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ScrollablePlaylistRow(
      itemCount: spotify.length,
      itemBuilder: (_, i) {
        final p = spotify[i];
        return PlaylistCard(
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          imageUrl: p['imageUrl'],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistTracksScreen(
              playlistId: p['id'] ?? '',
              playlistName: p['name'] ?? '',
              imageUrl: p['imageUrl'],
            ),
          )),
        );
      },
    );
  }

  Widget _buildOtherPlaylistsTab() {
    final other = _playlists
        .where((p) => p['isCustom'] != true && p['spotifyId'] == null)
        .toList();
    if (other.isEmpty) {
      return Center(
        child: Text('Нет других плейлистов',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ScrollablePlaylistRow(
      itemCount: other.length,
      itemBuilder: (_, i) {
        final p = other[i];
        return PlaylistCard(
          name: p['name'] ?? '',
          description: p['description'] ?? '',
          imageUrl: p['imageUrl'],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistTracksScreen(
              playlistId: p['id'] ?? '',
              playlistName: p['name'] ?? '',
              imageUrl: p['imageUrl'],
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
        await _loadPlaylists(); 
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
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
    final width = MediaQuery.of(context).size.width;
    const desktopBreakpoint = 900;
    final isDesktop = width >= desktopBreakpoint;

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

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(['Главная', 'Друзья', 'Профиль'][_currentIndex]),
              actions: [
                IconButton(
                  icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode),
                  onPressed: () => themeProvider.toggleTheme(),
                ),
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
              ],
            ),
      body: isDesktop
          ? Row(
              children: [
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
                      // extended: _railExpanded,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18.0),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('SyncM', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode),
                            onPressed: () => themeProvider.toggleTheme(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                      selectedIndex: _currentIndex,
                      onDestinationSelected: (i) => setState(() => _currentIndex = i),
                      // labelType: NavigationRailLabelType.all,
                      destinations: [
                        NavigationRailDestination(
                          icon: _RailIconWidget(icon: Icons.home, selected: _currentIndex == 0),
                          selectedIcon: _RailIconWidget(icon: Icons.home, selected: _currentIndex == 0),
                          label: const Text('Главная'),
                        ),
                        NavigationRailDestination(
                          icon: _RailIconWidget(icon: Icons.people, selected: _currentIndex == 1),
                          selectedIcon: _RailIconWidget(icon: Icons.people, selected: _currentIndex == 1),
                          label: const Text('Друзья'),
                        ),
                        NavigationRailDestination(
                          icon: _RailIconWidget(icon: Icons.person, selected: _currentIndex == 2),
                          selectedIcon: _RailIconWidget(icon: Icons.person, selected: _currentIndex == 2),
                          label: const Text('Профиль'),
                        ),
                        NavigationRailDestination(
                          icon: _RailIconWidget(icon: Icons.settings, selected: _currentIndex == 3),
                          selectedIcon: _RailIconWidget(icon: Icons.settings, selected: _currentIndex == 3),
                          label: const Text('Настройки'),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _buildDesktopHeader(),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: tabsDesktop[_currentIndex],
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
            )
          : tabsMobile[_currentIndex],
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
              top: false,
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? CupertinoTabBar(
                      currentIndex: _currentIndex,
                      onTap: (i) => setState(() => _currentIndex = i),
                      activeColor: Theme.of(context).colorScheme.primary,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.home),
                          label: 'Главная',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.people),
                          label: 'Друзья',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.person),
                          label: 'Профиль',
                        ),
                      ],
                    )
                  : BottomNavigationBar(
                      currentIndex: _currentIndex,
                      onTap: (i) => setState(() => _currentIndex = i),
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.home),
                          label: 'Главная',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.people),
                          label: 'Друзья',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.person),
                          label: 'Профиль',
                        ),
                      ],
                    ),
            ),
    );
  }
}
