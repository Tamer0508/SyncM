import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/notifications.dart';
import '../../widgets/track_card.dart';

class PickPlaylistScreen extends StatefulWidget {
  const PickPlaylistScreen({Key? key}) : super(key: key);

  @override
  State<PickPlaylistScreen> createState() => _PickPlaylistScreenState();
}

class _PickPlaylistScreenState extends State<PickPlaylistScreen> {
  List<dynamic> _playlists = [];
  List<dynamic> _tracks = [];
  Map<String, dynamic>? _selectedPlaylist;
  Set<String> _selectedTrackUris = {};
  bool _loadingPlaylists = true;
  bool _loadingTracks = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final playlists = await api.getPlaylists();
      if (mounted) setState(() => _playlists = playlists);
    } catch (e) {
      if (mounted) showAppNotification(context, message: 'Ошибка загрузки плейлистов', type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _loadingPlaylists = false);
    }
  }

  Future<void> _selectPlaylist(Map<String, dynamic> playlist) async {
    setState(() {
      _selectedPlaylist = playlist;
      _tracks = [];
      _selectedTrackUris = {};
      _loadingTracks = true;
    });

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final tracks = await api.getPlaylistTracks(playlist['id']);
      if (mounted) setState(() => _tracks = tracks);
    } catch (e) {
      if (mounted) showAppNotification(context, message: 'Ошибка загрузки треков', type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _loadingTracks = false);
    }
  }

  Future<void> _addTracks(String sessionId) async {
    final toAdd = _selectedTrackUris.isEmpty
        ? _tracks
        : _tracks.where((t) => _selectedTrackUris.contains(t['uri'])).toList();

    if (toAdd.isEmpty) {
      showAppNotification(context, message: 'Выберите треки', type: NotificationType.error);
      return;
    }

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      await api.addTracks(sessionId, toAdd.map<Map<String, dynamic>>((t) => {
        'spotifyUri': t['uri'],
        'trackName': t['name'],
        'artistName': t['artist'],
        'imageUrl': t['imageUrl'],
        'durationMs': t['durationMs'],
      }).toList());

      if (mounted) {
        showAppNotification(context, message: 'Добавлено ${toAdd.length} треков!', type: NotificationType.success);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showAppNotification(context, message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionId = ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedPlaylist == null ? 'Выберите плейлист' : _selectedPlaylist!['name']),
        leading: _selectedPlaylist != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selectedPlaylist = null;
                  _tracks = [];
                  _selectedTrackUris = {};
                }),
              )
            : null,
        actions: [
          if (_selectedPlaylist != null && _tracks.isNotEmpty)
            TextButton(
              onPressed: () => _addTracks(sessionId ?? ''),
              child: Text(
                _selectedTrackUris.isEmpty
                    ? 'Добавить всё (${_tracks.length})'
                    : 'Добавить (${_selectedTrackUris.length})',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: _selectedPlaylist == null ? _buildPlaylistList(theme) : _buildTrackList(theme),
    );
  }

  Widget _buildPlaylistList(ThemeData theme) {
    if (_loadingPlaylists) return const Center(child: CircularProgressIndicator());
    if (_playlists.isEmpty) return const Center(child: Text('Нет плейлистов'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _playlists.length,
      itemBuilder: (_, i) {
        final p = _playlists[i];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _selectPlaylist(Map<String, dynamic>.from(p)),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: p['imageUrl'] != null
                  ? Image.network(p['imageUrl'], width: 48, height: 48, fit: BoxFit.cover)
                  : Container(width: 48, height: 48, color: theme.colorScheme.surfaceVariant,
                      child: const Icon(Icons.music_note)),
            ),
            title: Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('${p['trackCount'] ?? 0} треков'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildTrackList(ThemeData theme) {
    if (_loadingTracks) return const Center(child: CircularProgressIndicator());
    if (_tracks.isEmpty) return const Center(child: Text('Нет треков'));

    return Column(
      children: [
        // Кнопка выбрать все
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  if (_selectedTrackUris.length == _tracks.length) {
                    _selectedTrackUris = {};
                  } else {
                    _selectedTrackUris = _tracks.map((t) => t['uri'] as String).toSet();
                  }
                }),
                icon: Icon(_selectedTrackUris.length == _tracks.length
                    ? Icons.deselect : Icons.select_all),
                label: Text(_selectedTrackUris.length == _tracks.length
                    ? 'Снять всё' : 'Выбрать всё'),
              ),
              const Spacer(),
              Text('${_selectedTrackUris.isEmpty ? _tracks.length : _selectedTrackUris.length} треков',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _tracks.length,
            itemBuilder: (_, i) {
              final t = _tracks[i];
              final uri = t['uri'] as String? ?? '';
              final selected = _selectedTrackUris.contains(uri);

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TrackCard(
                  id: uri,
                  title: t['name'] ?? '',
                  artist: t['artist'] ?? '',
                  artworkUrl: t['imageUrl'] as String?,
                  durationMs: t['durationMs'] as int?,
                  selected: selected,
                  showLike: false,
                  showMore: false,
                  trailing: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? theme.colorScheme.primary : null,
                    size: 20,
                  ),
                  onPlay: () => setState(() {
                    if (selected) {
                      _selectedTrackUris.remove(uri);
                    } else {
                      _selectedTrackUris.add(uri);
                    }
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}