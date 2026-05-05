import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/playlist_card.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../playlist/playlist_tracks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<dynamic> _playlists = [];
  bool _loadingPlaylists = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    if (mounted) setState(() => _loadingPlaylists = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final playlists = await api.getPlaylists();
      if (mounted) setState(() => _playlists = playlists);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки плейлистов: $e')));
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
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: Padding(
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
        ),
        const SizedBox(height: 20),
        Text('Мои плейлисты', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: _loadingPlaylists
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : _playlists.isEmpty
                  ? Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                          child: Text('Плейлисты еще не загружены или их нет в вашей библиотеке.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)), textAlign: TextAlign.center),
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final p = _playlists[i];
                        return PlaylistCard(
                          name: p['name'] ?? '',
                          description: p['description'] ?? '',
                          imageUrl: p['imageUrl'],
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PlaylistTracksScreen(
                                playlistId: p['id'] ?? '',
                                playlistName: p['name'] ?? '',
                                imageUrl: p['imageUrl'],
                              ),
                            ));
                          },
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final tabs = [
      _buildHomeTab(),
      const FriendsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(['Главная', 'Друзья', 'Профиль'][_currentIndex]),
        actions: [
          IconButton(
            icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.person_search),
              onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
            ),
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).pushNamed('/session/create'),
            ),
        ],
      ),
      body: tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
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
    );
  }
}
