import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_card.dart';

class PickPlaylistScreen extends StatefulWidget {
  const PickPlaylistScreen({super.key});

  @override
  State<PickPlaylistScreen> createState() => _PickPlaylistScreenState();
}

class _PickPlaylistScreenState extends State<PickPlaylistScreen> {
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _tracks = [];
  Map<String, dynamic>? _selectedPlaylist;
  final Set<String> _selectedTrackUris = {};

  bool _loadingPlaylists = true;
  bool _loadingTracks = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPlaylists();
    });
  }

  Future<void> _loadPlaylists() async {
    setState(() => _loadingPlaylists = true);
    try {
      final api = context.read<AuthProvider>().api;
      final playlists = await api.getPlaylists();
      if (!mounted) return;
      setState(() => _playlists = playlists.whereType<Map>().map(Map<String, dynamic>.from).toList());
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loadingPlaylists = false);
    }
  }

  Future<void> _selectPlaylist(Map<String, dynamic> playlist) async {
    setState(() {
      _selectedPlaylist = playlist;
      _tracks = [];
      _selectedTrackUris.clear();
      _loadingTracks = true;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final tracks = await api.getPlaylistTracks(playlist['id'] as String);
      if (!mounted) return;
      setState(() => _tracks = tracks.whereType<Map>().map(Map<String, dynamic>.from).toList());
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loadingTracks = false);
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedPlaylist = null;
      _tracks = [];
      _selectedTrackUris.clear();
    });
  }

  Future<void> _addTracks(String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) {
      showError(context, 'Не удалось определить сессию', force: true);
      return;
    }

    final toAdd = _selectedTrackUris.isEmpty
        ? _tracks
        : _tracks.where((t) => _selectedTrackUris.contains(t['uri'])).toList();

    if (toAdd.isEmpty) {
      showError(context, 'В плейлисте нет треков', force: true);
      return;
    }

    setState(() => _adding = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.addTracks(
        sessionId,
        toAdd
            .map<Map<String, dynamic>>((t) => {
                  'spotifyUri': t['uri'],
                  'trackName': t['name'],
                  'artistName': t['artist'],
                  'imageUrl': t['imageUrl'],
                  'durationMs': t['durationMs'],
                })
            .toList(),
      );

      if (!mounted) return;
      showSuccess(context, 'Добавлено ${toAdd.length} ${_plural(toAdd.length)}');
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  String _plural(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'треков';
    return switch (count % 10) {
      1 => 'трек',
      2 || 3 || 4 => 'трека',
      _ => 'треков',
    };
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ModalRoute.of(context)?.settings.arguments as String?;
    final inPlaylist = _selectedPlaylist != null;
    final selectedCount = _selectedTrackUris.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(inPlaylist ? _selectedPlaylist!['name'] as String? ?? 'Плейлист' : 'Выберите плейлист'),
        leading: inPlaylist
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'К списку плейлистов',
                onPressed: _clearSelection,
              )
            : null,
        actions: [
          if (inPlaylist && _tracks.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (selectedCount == _tracks.length) {
                  _selectedTrackUris.clear();
                } else {
                  _selectedTrackUris
                    ..clear()
                    ..addAll(_tracks.map((t) => t['uri'] as String));
                }
              }),
              child: Text(selectedCount == _tracks.length ? 'Снять всё' : 'Выбрать всё'),
            ),
        ],
      ),
      body: inPlaylist ? _buildTracks() : _buildPlaylists(),
      bottomNavigationBar: inPlaylist && _tracks.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton.icon(
                  onPressed: _adding ? null : () => _addTracks(sessionId),
                  icon: _adding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_rounded),
                  label: Text(
                    selectedCount == 0
                        ? 'Добавить все (${_tracks.length})'
                        : 'Добавить выбранные ($selectedCount)',
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPlaylists() {
    if (_loadingPlaylists) {
      return const SingleChildScrollView(child: SkeletonList(itemCount: 6));
    }

    if (_playlists.isEmpty) {
      return _EmptyView(
        icon: Icons.library_music_outlined,
        title: 'Плейлистов нет',
        subtitle: 'Подключите Spotify или создайте свой плейлист, '
            'чтобы добавлять треки в сессии.',
        onRetry: _loadPlaylists,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPlaylists,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _playlists.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) => _PlaylistTile(
          playlist: _playlists[i],
          onTap: () => _selectPlaylist(_playlists[i]),
        ),
      ),
    );
  }

  Widget _buildTracks() {
    if (_loadingTracks) {
      return const SingleChildScrollView(child: SkeletonList(itemCount: 8));
    }

    if (_tracks.isEmpty) {
      return _EmptyView(
        icon: Icons.music_off_rounded,
        title: 'Треков нет',
        subtitle: 'Этот плейлист пуст либо его содержимое недоступно: '
            'Spotify отдаёт треки только для ваших собственных плейлистов.',
        onRetry: _clearSelection,
        retryLabel: 'К списку плейлистов',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      itemCount: _tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final track = _tracks[i];
        final uri = track['uri'] as String?;
        final selected = uri != null && _selectedTrackUris.contains(uri);

        return TrackCard(
          id: uri ?? '$i',
          title: track['name'] as String? ?? 'Без названия',
          artist: track['artist'] as String? ?? '',
          artworkUrl: track['imageUrl'] as String?,
          durationMs: (track['durationMs'] as num?)?.toInt(),
          isActive: selected,
          showLike: false,
          showMore: false,
          onPlay: () {
            if (uri == null) return;
            setState(() {
              if (selected) {
                _selectedTrackUris.remove(uri);
              } else {
                _selectedTrackUris.add(uri);
              }
            });
          },
          trailing: Checkbox(
            value: selected,
            onChanged: uri == null
                ? null
                : (value) => setState(() {
                      if (value == true) {
                        _selectedTrackUris.add(uri);
                      } else {
                        _selectedTrackUris.remove(uri);
                      }
                    }),
          ),
        );
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final Map<String, dynamic> playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final trackCount = (playlist['trackCount'] as num?)?.toInt() ?? 0;

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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: AppRadius.small,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.queue_music_rounded, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist['name'] as String? ?? 'Без названия',
                      style: texts.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trackCount > 0 ? '$trackCount в плейлисте' : 'Пусто',
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
    this.retryLabel = 'Обновить',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: colors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: texts.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}