import 'dart:async';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../widgets/mini_player.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/playlists_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/image_cache.dart';
import '../../utils/local_store.dart';
import '../../utils/notifications.dart';
import '../../widgets/add_to_playlist_sheet.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/playlist_actions.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_card.dart';
import '../player/now_playing.dart';

/// Действия над отдельным треком внутри плейлиста.
enum _TrackAction { addToPlaylist, removeFromPlaylist }

enum TrackListSource {
  custom,

  spotifyPlaylist,

  spotifySaved,
}

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;
  final TrackListSource source;
  final bool embedded;

  /// Вызывается, когда плейлист удалили изнутри его же экрана.
  ///
  /// Во встроенной раскладке закрыть себя экран не может — панель показывает
  /// не он, а главный экран, и убрать её должен тоже он.
  final VoidCallback? onDeleted;

  const PlaylistTracksScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
    bool isCustom = false,
    this.embedded = false,
    this.onDeleted,
  }) : source =
            isCustom ? TrackListSource.custom : TrackListSource.spotifyPlaylist;

  const PlaylistTracksScreen.spotifySaved({
    super.key,
    required this.playlistName,
    this.embedded = false,
  })  : source = TrackListSource.spotifySaved,
        playlistId = '',
        imageUrl = null,
        onDeleted = null;

  bool get isCustom => source == TrackListSource.custom;

  bool get isSpotifyPlaylist => source == TrackListSource.spotifyPlaylist;

  bool get isSpotifySaved => source == TrackListSource.spotifySaved;

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<Map<String, dynamic>> _tracks = const [];
  bool _loading = true;
  String? _error;
  bool _unavailable = false;
  Map<String, bool> _likedMap = {};

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  /// Живая версия плейлиста из провайдера.
  ///
  /// Переименование и смена обложки должны быть видны здесь сразу, а не после
  /// возврата в список: аргументы конструктора — снимок на момент открытия и
  /// про изменения не знают.
  Map<String, dynamic> get _playlist {
    if (widget.isSpotifySaved) {
      return {
        'name': widget.playlistName,
        'description': L.of(context).spotifyLikedSubtitle,
        'trackCount': _tracks.length,
      };
    }

    final live = context.watch<PlaylistsProvider>().byId(widget.playlistId);
    return live ??
        {
          'id': widget.playlistId,
          'name': widget.playlistName,
          'imageUrl': widget.imageUrl,
          'isCustom': widget.isCustom,
          'trackCount': _tracks.length,
        };
  }

  Future<void> _loadTracks({bool refresh = false}) async {
    if (mounted && refresh) setState(() => _loading = true);

    try {
      final playlists = context.read<PlaylistsProvider>();
      final api = context.read<AuthProvider>().api;

      final likedRequest = api.getLikedTracks();
      likedRequest.ignore();

      final tracks = widget.isSpotifySaved
          ? await playlists.savedTracks(refresh: refresh)
          : await playlists.tracksOf(
              widget.playlistId,
              isCustom: widget.isCustom,
              refresh: refresh,
            );

      if (tracks == null) {
        // Доступ закрыт — показываем объяснение, а не ошибку.
        if (mounted) setState(() => _unavailable = true);
        return;
      }

      final likedTracks = await likedRequest;
      final likedMap = <String, bool>{};
      for (final track in likedTracks) {
        final uri = track['spotifyUri'] as String?;
        if (uri != null) likedMap[uri] = true;
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _likedMap = likedMap;
          _unavailable = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = getUserFriendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Воспроизведение ----------

  Future<void> _onTrackTap(
    Map<String, dynamic> track,
    int index, {
    List<Map<String, dynamic>>? queue,
  }) async {
    final uri = track['uri'] as String?;
    final trackName = track['name'] as String? ?? '';
    final artistName = track['artist'] as String? ?? '';
    if (uri == null || uri.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final api = auth.api;
    final pb = context.read<PlaybackProvider>();

    unawaited(api.logPlay(
      uri,
      trackName,
      artistName,
      imageUrl: track['imageUrl'] as String?,
    ));

    if (_isWindows) {
      if (auth.user?.spotifyConnected != true) {
        if (mounted) {
          showAppNotification(context,
              message: L.of(context).playlistConnectSpotifyHint,
              type: NotificationType.error);
        }
        return;
      }
    } else if (!pb.isConnected) {
      final connected = await pb.connect();
      if (!connected) {
        if (mounted) {
          showAppNotification(context,
              message: L.of(context).playbackSpotifyConnectFailed,
              type: NotificationType.error);
        }
        return;
      }
    }

    await pb.playTrack(
      {
        'title': track['name'],
        'artist': track['artist'],
        'imageUrl': track['imageUrl'],
        'uri': uri,
        'index': index,
        'contextIndex': track['contextIndex'],
      },
      playlistId: widget.isSpotifyPlaylist ? widget.playlistId : null,
      knownPlaylistTracks: queue ?? _tracks,
    );

    if (!mounted) return;

    final autoOpen =
        LocalStore.readBool(StoreKeys.autoOpenPlayer, defaultValue: true);

    if (!context.layout.showNowPlayingPanel && autoOpen) {
      // Не ждём закрытия плеера: он живёт до тех пор, пока его не свернут, а
      // запуску трека это никак не мешает.
      unawaited(NowPlayingScreen.open(
        context,
        title: track['name'] as String?,
        artist: track['artist'] as String?,
        artworkUrl: track['imageUrl'] as String?,
      ));
    }
  }

  Future<void> _playAll() async {
    if (_tracks.isEmpty) return;
    await _onTrackTap(_tracks.first, 0);
  }

  Future<void> _shuffle() async {
    if (_tracks.isEmpty) return;
    final random = Random();

    if (widget.isSpotifyPlaylist) {
      await context.read<PlaybackProvider>().setShuffle(true);
      if (!mounted) return;
      final index = random.nextInt(_tracks.length);
      await _onTrackTap(_tracks[index], index);
      return;
    }

    final shuffled = List<Map<String, dynamic>>.from(_tracks)..shuffle(random);
    await _onTrackTap(shuffled.first, 0, queue: shuffled);
  }

  // ---------- Изменение списка ----------

  Future<void> _removeTrack(Map<String, dynamic> track) async {
    final uri = track['uri'] as String?;
    if (uri == null || uri.isEmpty) return;

    // Убираем из списка сразу: удаление своего же трека не та операция, ради
    // которой стоит смотреть на спиннер. При отказе сервера список
    // возвращается на место.
    final previous = _tracks;
    setState(() => _tracks = _tracks.where((t) => t['uri'] != uri).toList());

    try {
      await context.read<PlaylistsProvider>().removeTrack(widget.playlistId, uri);
      if (mounted) showSuccess(context, L.of(context).playlistTrackRemoved);
    } catch (err) {
      if (!mounted) return;
      setState(() => _tracks = previous);
      showError(context, err);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    // ReorderableList отдаёт newIndex по состоянию «до» изъятия элемента.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final previous = _tracks;
    final next = List<Map<String, dynamic>>.from(_tracks);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    setState(() => _tracks = next);

    try {
      await context.read<PlaylistsProvider>().reorderTracks(
            widget.playlistId,
            next.map((t) => t['uri'] as String? ?? '').where((u) => u.isNotEmpty).toList(),
          );
    } catch (err) {
      if (!mounted) return;
      setState(() => _tracks = previous);
      showError(context, err);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> track) async {
    final uri = track['uri'] as String? ?? '';
    if (uri.isEmpty) return;

    try {
      final api = context.read<AuthProvider>().api;
      final liked = await api.toggleLike(
        uri,
        track['name'] as String? ?? '',
        track['artist'] as String? ?? '',
        imageUrl: track['imageUrl'] as String?,
      );
      if (!mounted) return;
      setState(() {
        if (liked) {
          _likedMap[uri] = true;
        } else {
          _likedMap.remove(uri);
        }
      });
    } catch (e) {
      // showError вместо 'Ошибка: $e': текст исключения пользователю ничего
      // не объясняет.
      if (mounted) showError(context, e);
    }
  }

  void _onPlaylistDeleted() {
    if (widget.embedded) {
      widget.onDeleted?.call();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- Разметка ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playlist = _playlist;

    // Играющий трек читаем здесь, один раз на весь список.
    //
    // Раньше каждая строка спрашивала провайдер сама — но строит их
    // itemBuilder, который вызывается лениво, уже вне build этого виджета, а
    // context.select там запрещён: приложение падало красным экраном сразу
    // после добавления трека. Заодно так дешевле: одна подписка вместо одной
    // на каждую строку.
    final activeUri = context.select<PlaybackProvider, String?>(
      (pb) => pb.currentTrack?['uri'] as String?,
    );
    final wide = context.isWideWindow;

    final content = CustomScrollView(
      slivers: [
        _buildAppBar(theme, playlist),
        if (!_unavailable && _error == null)
          SliverToBoxAdapter(child: _buildHeaderActions(playlist)),
        if (_loading && _tracks.isEmpty)
          SliverToBoxAdapter(
            child: SkeletonTrackList(
              itemCount: 8,
              // Отступы списка треков: сверху и по бокам — от SliverPadding,
              // снизу к ним добавляется промежуток после последней строки.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm + AppSpacing.xs,
              ),
              showLike: true,
              trailing: widget.isCustom && wide
                  ? SkeletonTrackTrailing.menuAndHandle
                  : SkeletonTrackTrailing.menu,
            ),
          )
        else if (_unavailable)
          SliverFillRemaining(
            hasScrollBody: false,
            child: widget.isSpotifySaved
                ? _Notice(
                    icon: Icons.link_off_rounded,
                    message: L.of(context).homeSpotifyUnavailableHint,
                  )
                : _Notice(
                    icon: Icons.lock_outline_rounded,
                    message: L.of(context).playlistForeign,
                  ),
          )
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ),
          )
        else if (_tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmpty(playlist),
          )
        else
          _buildTrackSliver(activeUri: activeUri, wide: wide),
      ],
    );

    if (widget.embedded) {
      return content; // только список: шапку рисует главный экран
    }

    return Scaffold(
      bottomNavigationBar: const MiniPlayerDock(),
      backgroundColor: theme.colorScheme.surface,
      body: content,
    );
  }

  Widget _buildAppBar(ThemeData theme, Map<String, dynamic> playlist) {
    if (widget.embedded) {
      return const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm));
    }

    final imageUrl = playlist.playlistImageUrl;

    // SliverAppBar.large вместо ручной сборки: у него уже настроено поведение
    // крупного заголовка по Material 3 — размер, отступы и переход к
    // компактному виду при прокрутке.
    return SliverAppBar.large(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      title: Text(
        playlist.playlistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (!widget.isSpotifySaved)
          PlaylistActionsButton(
            playlist: playlist,
            includeOpen: false,
            onDeleted: _onPlaylistDeleted,
            onTracksChanged: () => _loadTracks(refresh: true),
            iconColor: theme.colorScheme.onSurface,
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    ColoredBox(color: theme.colorScheme.primaryContainer),
                errorWidget: (_, _, _) =>
                    ColoredBox(color: theme.colorScheme.primaryContainer),
              )
            else if (widget.isSpotifySaved)
              ColoredBox(
                color: theme.colorScheme.primaryContainer,
                child: Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 72,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            else
              ColoredBox(color: theme.colorScheme.primaryContainer),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    theme.colorScheme.surface.withValues(alpha: 0.55),
                    theme.colorScheme.surface,
                  ],
                  stops: const [0.35, 0.8, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Строка над списком: слушать, перемешать и — во встроенной раскладке —
  /// меню действий, которого там нет в шапке.
  Widget _buildHeaderActions(Map<String, dynamic> playlist) {
    final hasTracks = _tracks.isNotEmpty;
    final description = playlist.playlistDescription;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) ...[
            Text(
              description,
              style: context.texts.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (hasTracks) ...[
            Text(
              _summary(),
              style: context.texts.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
          ] else
            const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Flexible(
                child: FilledButton.icon(
                  onPressed: hasTracks ? _playAll : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    L.of(context).playlistPlay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: OutlinedButton.icon(
                  onPressed: hasTracks ? _shuffle : null,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: Text(
                    L.of(context).playerShuffle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.embedded && !widget.isSpotifySaved)
                PlaylistActionsButton(
                  playlist: playlist,
                  includeOpen: false,
                  onDeleted: _onPlaylistDeleted,
                  onTracksChanged: () => _loadTracks(refresh: true),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// «12 треков · 47 мин» — сведения о плейлисте там, где на них смотрят.
  ///
  /// Отдельного окна «Информация» для двух чисел не нужно: их читают перед
  /// тем, как включить, а не по особому запросу.
  String _summary() {
    final l = L.of(context);
    final tracks = l.trackCount(_tracks.length);

    final totalMs = _tracks.fold<int>(
      0,
      (sum, track) => sum + ((track['durationMs'] as num?)?.toInt() ?? 0),
    );

    if (totalMs <= 0) return tracks;

    final minutes = totalMs ~/ 60000;
    if (minutes < 60) return '$tracks · ${l.durationMinutes(minutes)}';

    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final duration = rest > 0
        ? '${l.durationHours(hours)} ${l.durationMinutes(rest)}'
        : l.durationHours(hours);

    return '$tracks · $duration';
  }

  Widget _buildEmpty(Map<String, dynamic> playlist) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isSpotifySaved
                  ? Icons.favorite_border_rounded
                  : Icons.music_off_rounded,
              size: 40,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            Text(
              widget.isSpotifySaved
                  ? L.of(context).spotifyLikedTitle
                  : L.of(context).playlistEmptyTitle,
              style: context.texts.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.isCustom
                  ? L.of(context).playlistEmptyMessage
                  : widget.isSpotifySaved
                      ? L.of(context).spotifyLikedEmpty
                      : L.of(context).playlistEmptyShort,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (widget.isCustom) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.library_add_rounded),
                label: Text(L.of(context).playlistAddMusic),
                onPressed: () => runPlaylistAction(
                  context,
                  PlaylistAction.addMusic,
                  playlist,
                  onTracksChanged: () => _loadTracks(refresh: true),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Список треков.
  ///
  /// В своём плейлисте — перетаскиваемый: порядок задаёт человек, и хранится
  /// он на сервере. В чужом порядок задаёт Spotify, и делать вид, что его
  /// можно поменять, нельзя — там обычный список.
  Widget _buildTrackSliver({required String? activeUri, required bool wide}) {
    const padding = EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    );

    if (!widget.isCustom) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.builder(
          itemCount: _tracks.length,
          itemBuilder: (context, i) =>
              _buildTrackCard(context, i, activeUri: activeUri, wide: wide),
        ),
      );
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverReorderableList(
        itemCount: _tracks.length,
        onReorder: _reorder,
        itemBuilder: (context, i) =>
            _buildTrackCard(context, i, activeUri: activeUri, wide: wide),
        // Плавающая копия строки во время перетаскивания: без неё строка
        // теряет фон списка и на тёмной теме превращается в текст на пустоте.
        proxyDecorator: (child, index, animation) => Material(
          color: context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.row),
          elevation: 6,
          child: child,
        ),
      ),
    );
  }

  /// Строка трека.
  ///
  /// [context] — именно тот, что дал itemBuilder, а не context самого экрана:
  /// строки строятся лениво при прокрутке, и обращаться отсюда к состоянию
  /// экрана как к своему нельзя.
  Widget _buildTrackCard(
    BuildContext context,
    int index, {
    required String? activeUri,
    required bool wide,
  }) {
    final track = _tracks[index];
    final uri = track['uri'] as String? ?? '';
    final isActive = uri.isNotEmpty && uri == activeUri;

    final card = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: TrackCard(
        id: track['id'] as String? ?? uri,
        title: track['name'] as String? ?? '',
        artist: track['artist'] as String? ?? '',
        artworkUrl: track['imageUrl'] as String?,
        durationMs: (track['durationMs'] as num?)?.toInt(),
        isLiked: _likedMap[uri] ?? false,
        isActive: isActive,
        onPlay: () => _onTrackTap(track, index),
        onLike: () => _toggleLike(track),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppMenuButton<_TrackAction>(
              iconColor: context.colors.onSurfaceVariant,
              tooltip: L.of(context).playlistTrackActions,
              onSelected: (action) => switch (action) {
                _TrackAction.addToPlaylist => showAddToPlaylistSheet(context, track),
                _TrackAction.removeFromPlaylist => _removeTrack(track),
              },
              entries: [
                AppMenuEntry(
                  value: _TrackAction.addToPlaylist,
                  icon: Icons.playlist_add_rounded,
                  label: L.of(context).addToPlaylistTitle,
                ),
                if (widget.isCustom)
                  // Именно «из плейлиста»: трек остаётся и в Spotify, и в
                  // остальных плейлистах — здесь удаляется только строка
                  // этого списка.
                  AppMenuEntry(
                    value: _TrackAction.removeFromPlaylist,
                    icon: Icons.playlist_remove_rounded,
                    label: L.of(context).playlistRemoveTrack,
                    danger: true,
                    separated: true,
                  ),
              ],
            ),
            if (widget.isCustom && wide) _buildDragHandle(context, index),
          ],
        ),
      ),
    );

    if (!widget.isCustom) {
      return KeyedSubtree(key: ValueKey(uri.isEmpty ? '$index' : uri), child: card);
    }

    // Долгое нажатие на самой строке — привычный способ перетащить на
    // сенсорном экране; на десктопе для этого есть ручка справа.
    return ReorderableDelayedDragStartListener(
      key: ValueKey(uri.isEmpty ? '$index' : uri),
      index: index,
      enabled: !wide,
      child: card,
    );
  }

  Widget _buildDragHandle(BuildContext context, int index) {
    return ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Icon(
            Icons.drag_indicator_rounded,
            size: 20,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

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
              message,
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
