import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/playlists_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/pill_selector.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_card.dart';

class AddTracksScreen extends StatefulWidget {
  const AddTracksScreen({super.key, required this.playlist});

  final Map<String, dynamic> playlist;

  static Future<bool?> open(BuildContext context, Map<String, dynamic> playlist) {
    if (context.isWideWindow) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: AddTracksScreen(playlist: playlist),
          ),
        ),
      );
    }

    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTracksScreen(playlist: playlist),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<AddTracksScreen> createState() => _AddTracksScreenState();
}

class _AddTracksScreenState extends State<AddTracksScreen> {
  int _sourceIndex = 0;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<Map<String, dynamic>> _searchResults = const [];
  bool _searching = false;

  Map<String, dynamic>? _selectedSource;
  List<Map<String, dynamic>> _sourceTracks = const [];
  bool _loadingSourceTracks = false;
  bool _sourceUnavailable = false;

  Set<String> _existingUris = {};

  final Map<String, Map<String, dynamic>> _selected = {};

  bool _adding = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final playlists = context.read<PlaylistsProvider>();
    try {
      final tracks = await playlists.tracksOf(
        widget.playlist.playlistId,
        isCustom: true,
      );
      if (!mounted || tracks == null) return;
      setState(() {
        _existingUris = tracks
            .map((t) => t['uri'] as String?)
            .whereType<String>()
            .toSet();
      });
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  List<Map<String, dynamic>> get _sourcePlaylists {
    final playlists = context.watch<PlaylistsProvider>();
    final targetId = widget.playlist.playlistId;
    return [
      ...playlists.custom.where((p) => p.playlistId != targetId),
      ...playlists.spotify,
    ];
  }


  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _query = '';
        _searchResults = const [];
        _searching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _searching = true;
    });

    try {
      final api = context.read<PlaylistsProvider>().api;
      final results = await api.searchSpotifyTracks(query);
      if (!mounted || _query != query) return;
      setState(() {
        _searchResults =
            results.whereType<Map>().map(Map<String, dynamic>.from).toList();
      });
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }


  Future<void> _openSource(Map<String, dynamic> playlist) async {
    setState(() {
      _selectedSource = playlist;
      _sourceTracks = const [];
      _sourceUnavailable = false;
      _loadingSourceTracks = true;
    });

    try {
      final tracks = await context.read<PlaylistsProvider>().tracksOf(
            playlist.playlistId,
            isCustom: playlist.isCustomPlaylist,
          );
      if (!mounted) return;
      setState(() {
        _sourceTracks = tracks ?? const [];
        _sourceUnavailable = tracks == null;
      });
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _loadingSourceTracks = false);
    }
  }


  void _toggle(Map<String, dynamic> track) {
    final uri = track['uri'] as String?;
    if (uri == null || uri.isEmpty || _existingUris.contains(uri)) return;
    setState(() {
      if (_selected.containsKey(uri)) {
        _selected.remove(uri);
      } else {
        _selected[uri] = track;
      }
    });
  }

  Future<void> _add() async {
    if (_selected.isEmpty) return;

    setState(() => _adding = true);
    try {
      final payload = _selected.values
          .map<Map<String, dynamic>>((track) => {
                'trackUri': track['uri'],
                'trackName': track['name'],
                'artistName': track['artist'] ?? '',
                'imageUrl': track['imageUrl'],
                'durationMs': track['durationMs'],
              })
          .toList();

      final result = await context
          .read<PlaylistsProvider>()
          .addTracks(widget.playlist.playlistId, payload);

      if (!mounted) return;

      _changed = _changed || result.added > 0;
      setState(() {
        _existingUris.addAll(_selected.keys);
        _selected.clear();
        _adding = false;
      });

      showSuccess(context, _addedMessage(result.added, result.skipped));
    } catch (err) {
      if (!mounted) return;
      setState(() => _adding = false);
      showError(context, err);
    }
  }

  String _addedMessage(int added, int skipped) {
    final l = L.of(context);
    if (added == 0) return l.addTracksAllPresent;

    final base = l.addTracksAdded(added);
    return skipped == 0 ? base : l.addTracksAddedWithSkipped(base, skipped);
  }


  @override
  Widget build(BuildContext context) {
    final insideDialog = context.isWideWindow;
    final selectedCount = _selected.length;

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: PillSelector(
            labels: [L.of(context).addTracksSearch, L.of(context).addTracksFromPlaylist],
            selectedIndex: _sourceIndex,
            onSelected: (index) => setState(() => _sourceIndex = index),
          ),
        ),
        Expanded(
          child: _sourceIndex == 0 ? _buildSearchTab() : _buildFromPlaylistTab(),
        ),
        if (selectedCount > 0)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton.icon(
                onPressed: _adding ? null : _add,
                icon: _adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_rounded),
                label: Text(L.of(context).addTracksAddCount(selectedCount)),
              ),
            ),
          ),
      ],
    );

    final title = Text(
      L.of(context).addTracksToPlaylist(widget.playlist.playlistName),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (insideDialog) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(child: DefaultTextStyle.merge(style: context.texts.titleMedium!, child: title)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(_changed),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: L.of(context).commonClose,
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: title,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: L.of(context).commonBack,
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: body,
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            controller: _searchController,
            autofocus: !context.isWideWindow,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            onSubmitted: (value) {
              _searchDebounce?.cancel();
              final query = value.trim();
              if (query.isNotEmpty) _search(query);
            },
            decoration: InputDecoration(
              hintText: L.of(context).addTracksSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: L.of(context).commonClear,
                      onPressed: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searching && _searchResults.isEmpty) {
      return const SingleChildScrollView(
        child: SkeletonTrackList(
          itemCount: 6,
          trailing: SkeletonTrackTrailing.box,
        ),
      );
    }

    if (_query.isEmpty) {
      return _Hint(
        icon: Icons.search_rounded,
        text: L.of(context).addTracksSearchEmpty,
      );
    }

    if (_searchResults.isEmpty) {
      return _Hint(
        icon: Icons.search_off_rounded,
        text: L.of(context).addTracksNothingFound,
      );
    }

    return _buildTrackList(_searchResults);
  }

  Widget _buildFromPlaylistTab() {
    if (_selectedSource == null) {
      if (_sourcePlaylists.isEmpty) {
        return _Hint(
          icon: Icons.library_music_outlined,
          text: L.of(context).addTracksNoOtherPlaylists,
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xl,
        ),
        itemCount: _sourcePlaylists.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (_, i) {
          final playlist = _sourcePlaylists[i];
          return ListTile(
            leading: Icon(
              playlist.isCustomPlaylist
                  ? Icons.queue_music_rounded
                  : Icons.library_music_rounded,
              color: context.colors.onSurfaceVariant,
            ),
            title: Text(
              playlist.playlistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              playlist.isCustomPlaylist ? L.of(context).addTracksYourPlaylist : 'Spotify',
              style: context.texts.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSource(playlist),
          );
        },
      );
    }

    if (_loadingSourceTracks) {
      return const SingleChildScrollView(
        child: SkeletonTrackList(
          itemCount: 8,
          trailing: SkeletonTrackTrailing.box,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: L.of(context).addTracksBackToPlaylists,
                onPressed: () => setState(() {
                  _selectedSource = null;
                  _sourceTracks = const [];
                }),
              ),
              Expanded(
                child: Text(
                  _selectedSource!.playlistName,
                  style: context.texts.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_sourceTracks.isNotEmpty)
                TextButton(
                  onPressed: _toggleAllFromSource,
                  child: Text(_allSourceSelected ? L.of(context).addTracksDeselect : L.of(context).addTracksSelectAll),
                ),
            ],
          ),
        ),
        Expanded(
          child: _sourceUnavailable
              ? _Hint(
                  icon: Icons.lock_outline_rounded,
                  text: L.of(context).addTracksForeignPlaylist,
                )
              : _sourceTracks.isEmpty
                  ? _Hint(
                      icon: Icons.music_off_rounded,
                      text: L.of(context).addTracksEmptyPlaylist,
                    )
                  : _buildTrackList(_sourceTracks),
        ),
      ],
    );
  }

  Iterable<Map<String, dynamic>> get _selectableSourceTracks => _sourceTracks.where(
        (t) {
          final uri = t['uri'] as String?;
          return uri != null && uri.isNotEmpty && !_existingUris.contains(uri);
        },
      );

  bool get _allSourceSelected {
    final selectable = _selectableSourceTracks.toList();
    if (selectable.isEmpty) return false;
    return selectable.every((t) => _selected.containsKey(t['uri']));
  }

  void _toggleAllFromSource() {
    final selectable = _selectableSourceTracks.toList();
    final selectAll = !_allSourceSelected;
    setState(() {
      for (final track in selectable) {
        final uri = track['uri'] as String;
        if (selectAll) {
          _selected[uri] = track;
        } else {
          _selected.remove(uri);
        }
      }
    });
  }

  Widget _buildTrackList(List<Map<String, dynamic>> tracks) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final track = tracks[i];
        final uri = track['uri'] as String? ?? '';
        final already = _existingUris.contains(uri);
        final selected = _selected.containsKey(uri);

        return TrackCard(
          id: uri.isEmpty ? '$i' : uri,
          title: track['name'] as String? ?? L.of(context).historyUntitled,
          artist: track['artist'] as String? ?? '',
          artworkUrl: track['imageUrl'] as String?,
          durationMs: (track['durationMs'] as num?)?.toInt(),
          showLike: false,
          selected: selected,
          onPlay: already ? null : () => _toggle(track),
          trailing: SizedBox.square(
            dimension: 48,
            child: Center(
              child: already
                  ? Tooltip(
                      message: L.of(context).addTracksAlreadyIn,
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: context.colors.primary,
                      ),
                    )
                  : Checkbox(
                      value: selected,
                      onChanged: uri.isEmpty ? null : (_) => _toggle(track),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm + 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
