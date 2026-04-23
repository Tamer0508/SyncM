import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/playlist_card.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
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
      print('Error loading playlists: $e');
    } finally {
      if (mounted) setState(() => _loadingPlaylists = false);
    }
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Playlists',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: _loadingPlaylists
                  ? const Center(child: CircularProgressIndicator())
                  : _playlists.isEmpty
                      ? const Center(child: Text('Нет плейлистов'))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _playlists.length,
                          itemBuilder: (_, i) {
                          final p = _playlists[i];
                          return PlaylistCard(  // добавь return
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Sessions',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                    onPressed: () async {
                      await Provider.of<SessionProvider>(context, listen: false)
                          .fetchMySessions();
                    },
                    child: const Text('Refresh'))
              ],
            ),
            const SizedBox(height: 8),
            Consumer<SessionProvider>(builder: (_, prov, __) {
              if (prov.loading)
                return const Center(child: CircularProgressIndicator());
              if (prov.sessions.isEmpty)
                return const Center(child: Text('No active sessions'));
              return Column(
                children: prov.sessions
                    .map((s) => ListTile(
                          title: Text(s.name),
                          subtitle: Text('Host: ${s.id.substring(0, 6)}'),
                          onTap: () =>
                              Navigator.of(context).pushNamed('/session'),
                        ))
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildHomeTab(),
      const FriendsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(['Home', 'Friends', 'Profile'][_currentIndex]),
        actions: [
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.person_search),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/friends/search'),
            ),
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/session/create'),
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
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}