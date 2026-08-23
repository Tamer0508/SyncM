import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import 'package:syncm/screens/session/pick_playlist_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/playback_provider.dart';
import '../../utils/notifications.dart';
import '../player/now_playing.dart';
import '../../services/socket_service.dart';
import '../../models/sync_phase.dart';
import '../../theme.dart';
import '../../utils/local_store.dart';
import '../../utils/error_utils.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/tappable_avatar.dart';
import '../../widgets/sync_mark.dart';
import '../../widgets/track_card.dart';

class SessionScreen extends StatefulWidget {
  final bool embedded;
  final Map<String, dynamic>? sessionData;
  final VoidCallback? onBack;

  /// Сессия завершена — главный экран покажет итоги в центральной части.
  ///
  /// Во встроенном режиме переход отдельным маршрутом закрывал бы боковые
  /// панели, поэтому решение о показе принимает тот, кто нас встроил.
  final void Function(Map<String, dynamic> results)? onSessionEnded;

  const SessionScreen({
    super.key,
    this.embedded = false,
    this.sessionData,
    this.onBack,
    this.onSessionEnded,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? _session;
  bool _initialized = false;
  bool _refreshing = false;
  PlaybackProvider? _playback;
  Set<String> _onlineUserIds = {};
  bool _isPlayerOpen = false;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  void _syncSessionQueue() {
    if (_session == null) return;
    final tracks = _session!['tracks'] as List? ?? [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<PlaybackProvider>(context, listen: false)
          .setSessionQueue(tracks);
    });
  }

  void _openPlayerIfMobile(Map<String, dynamic> track) async {
    if (!mounted || _isPlayerOpen) return;
    if (context.layout.showNowPlayingPanel) return;
    // Настройка «Открывать плеер при запуске». Раньше она писалась в
    // хранилище и не читалась нигде — переключатель выглядел рабочим, но
    // ничего не менял.
    if (!LocalStore.readBool(StoreKeys.autoOpenPlayer, defaultValue: true)) {
      return;
    }
    _isPlayerOpen = true;


    // Панелью, а не маршрутом: экран сессии с очередью остаётся под ней и
    // продолжает получать события, а свайп вниз сворачивает плеер обратно.
    await NowPlayingScreen.open(
      context,
      title: track['title'] as String?,
      artist: track['artist'] as String?,
      artworkUrl: track['imageUrl'] as String?,
    );
    _isPlayerOpen = false;
  }

  void _setupPlaybackCallbacks() {
    _playback = Provider.of<PlaybackProvider>(context, listen: false);
    final pb = _playback!;
    pb.onTracksAdded = (data) async {
      if (!mounted) return;
      if (data['allTracks'] is List) {
        setState(() {
          _session = {
            ..._session!,
            'tracks': data['allTracks'],
          };
        });
        pb.setSessionQueue(data['allTracks'] as List);
      } else {
        await _refreshSession();
      }
    };
    pb.onSessionPlaybackStarted = _openPlayerIfMobile;
    pb.onPrepareError = (msg) {
      if (!mounted) return;
      showAppNotification(context, message: msg, type: NotificationType.error);
    };
  }

  Future<void> _onTrackTap(Map<String, dynamic> rawTrack, int index) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    final track = PlaybackProvider.mapSessionTrack(rawTrack, index);
    final uri = track['uri'] as String?;
    if (uri == null || uri.isEmpty) return;

    // История не должна задерживать старт трека.
    unawaited(auth.api.logPlay(
      uri,
      track['title'] as String? ?? '',
      track['artist'] as String? ?? '',
      imageUrl: track['imageUrl'] as String?,
    ));

    if (_isWindows && auth.user?.spotifyConnected != true) {
      if (mounted) {
        showAppNotification(context,
            message: 'Подключите Spotify аккаунт в профиле',
            type: NotificationType.error);
      }
      return;
    }

    if (!_isWindows) {
      if (!pb.isConnected) {
        final connected = await pb.connect();
        if (!connected && mounted) {
          showAppNotification(context,
              message: 'Не удалось подключиться к Spotify',
              type: NotificationType.error);
          return;
        }
      }
    }

    _syncSessionQueue();
    await pb.playSessionTrack(index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.sessionData != null) {
        _session = widget.sessionData;
      } else {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) _session = args;
      }
      if (_session != null) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final pb = Provider.of<PlaybackProvider>(context, listen: false);
        final socket = Provider.of<SocketService>(context, listen: false);
        final isHost = _session!['hostId'] == auth.user?.id;
        pb.initSession(_session!['id'], auth.user?.id ?? '', socket,
            isHost: isHost);
        _setupPlaybackCallbacks();
        _setupSessionSocketListeners(socket);
        _syncSessionQueue();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshSession();
        });
      }
    }
  }

  StreamSubscription<void>? _reconnectSub;

  /// Свои подписки на события сокета.
  final List<SocketSubscription> _subscriptions = [];

  void _setupSessionSocketListeners(SocketService socket) {
    // session_ended здесь НЕ обрабатывается — намеренно.
    //
    // Обработчик живёт в SessionProvider: он переживает пересоздание экрана и
    // знает, показать ли итоги встроенно или маршрутом. Дублирующий
    // обработчик здесь вёл к гонке (кто первым перейдёт — зависело от порядка
    // подписки) и переставал работать сразу после выхода из сессии, оставляя
    // участников в закрытой сессии.

    _subscriptions.addAll([
      socket.on('user_joined', (_) {
        if (mounted) _refreshSession();
      }),
      socket.on('session_presence', (data) {
        if (!mounted) return;
        final ids = (data is Map ? data['onlineUserIds'] : null);
        if (ids is List) {
          setState(() {
            _onlineUserIds = ids.map((e) => e.toString()).toSet();
          });
        }
      }),
      socket.on('participant_dropped', (data) {
        if (!mounted) return;
        _refreshSession();
      }),
      socket.on('host_changed', (data) {
        if (!mounted) return;
        final newHostId = (data is Map ? data['hostId'] : null)?.toString();
        if (newHostId == null) return;
        final auth = Provider.of<AuthProvider>(context, listen: false);
        setState(() {
          _session?['hostId'] = newHostId;
        });
        _playback?.updateHostStatus(newHostId == auth.user?.id);
        final becameHost = newHostId == auth.user?.id;
        showAppNotification(
          context,
          message: becameHost
              ? 'Вы теперь ведущий сессии'
              : 'Ведущий сессии сменился',
          type: NotificationType.info,
        );
      }),
    ]);

    _reconnectSub = socket.onReconnect.listen((_) {
      if (!mounted) return;
      _refreshSession();
    });
  }

  @override
  void dispose() {
    _playback?.onTracksAdded = null;
    _playback?.onSessionPlaybackStarted = null;
    _playback?.onPrepareError = null;
    _reconnectSub?.cancel();
    _subscriptions.cancelAll();
    super.dispose();
  }

  Future<void> _refreshSession() async {
    setState(() => _refreshing = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final sessions = await api.getMySessions();
      final updated = (sessions)
          .firstWhere((s) => s['id'] == _session!['id'], orElse: () => null);
      if (updated != null && mounted) {
        setState(() => _session = Map<String, dynamic>.from(updated));
        _syncSessionQueue();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _endSession() async {
    // Подтверждение можно отключить в настройках.
    //
    // Завершение необратимо и затрагивает второго участника, поэтому по
    // умолчанию спрашиваем. Но тем, кто закрывает сессии часто, лишний шаг
    // мешает — и это их выбор, а не наш.
    if (!LocalStore.readBool(StoreKeys.confirmEndSession, defaultValue: true)) {
      await _doEndSession();
      return;
    }

    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(children: [
                Icon(Icons.stop_circle,
                    color: theme.colorScheme.error, size: 28),
                const SizedBox(width: 12),
                Text('Завершить сессию?',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))
              ]),
              content: const Text('Сессия будет закрыта для всех участников.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Завершить')),
              ],
            ));
    if (confirm != true || !mounted) return;

    await _doEndSession();
  }

  /// Собственно завершение — без подтверждения.
  ///
  /// Выделено отдельно, чтобы вызываться и после диалога, и напрямую, когда
  /// подтверждение отключено в настройках.
  Future<void> _doEndSession() async {

    try {
      final result = await Provider.of<SessionProvider>(context, listen: false)
          .endSession(_session!['id']);

      if (mounted) {
        await context.read<PlaybackProvider>().stopAndClear();
      }

      if (mounted) {
        // Итоги показываем ВСЕГДА, в том числе во встроенном режиме.
        //
        // Раньше на широком экране хост просто закрывал панель через onBack
        // и на экран результатов не попадал вовсе: совпавшие треки, ради
        // которых сессия и затевалась, он не видел.
        //
        // Порядок важен: сначала закрываем встроенную панель, иначе после
        // возврата с результатов пользователь снова окажется в закрытой
        // сессии.
        final args = result ?? const <String, dynamic>{};

        if (widget.embedded && widget.onBack != null) {
          // Итоги показывает тот, кто нас встроил, — в центральной части,
          // с сохранением боковых панелей. Отдельный маршрут закрывал бы их.
          if (widget.onSessionEnded != null) {
            widget.onSessionEnded!(args);
          } else {
            widget.onBack!();
          }
          return;
        }

        Navigator.of(context).pushNamed('/session/results', arguments: args);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthProvider>();
    final myUserId = auth.user?.id;

    if (_session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final session = _session!;
    final members = (session['members'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final tracks = (session['tracks'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final isHost = session['hostId'] == myUserId;
    final sessionName = session['name'] as String? ?? 'Сессия';

    final content = RefreshIndicator(
      onRefresh: _refreshSession,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SessionHeader(
              members: members,
              onlineUserIds: _onlineUserIds,
              trackCount: tracks.length,
              // Ждём второго, пока он не в сети: провайдер про состав сессии
              // не знает, а экран знает — и вправе показать ожидание по
              // своей причине.
              waitingForOthers: members
                  .where((m) => m['status'] == 'accepted')
                  .any((m) => !_onlineUserIds.contains(m['userId'])),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyTracksView(onAddTracks: _openPlaylistPicker),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.xl * 3,
              ),
              sliver: SliverList.separated(
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final track = tracks[i].cast<String, dynamic>();
                  return _SessionTrackTile(
                    track: track,
                    index: i,
                    myUserId: myUserId,
                    onPlay: () => _onTrackTap(track, i),
                    onRate: (rating) => _rateTrack(track, rating),
                  );
                },
              ),
            ),
        ],
      ),
    );

    final actions = [
      IconButton(
        onPressed: _openPlaylistPicker,
        icon: const Icon(Icons.playlist_add_rounded),
        tooltip: 'Добавить треки',
      ),
      if (isHost)
        IconButton(
          onPressed: _endSession,
          icon: const Icon(Icons.stop_circle_outlined),
          tooltip: 'Завершить сессию',
          color: colors.error,
        ),
    ];

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: sessionName,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: actions,
      ),
      child: content,
    );
  }

  Future<void> _openPlaylistPicker() async {
    final sessionId = _session?['id'] as String?;
    if (sessionId == null) return;

    final isWide = context.isWideWindow;

    final Object? added;
    if (isWide) {
      added = await showDialog<Object?>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.extraLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: PickPlaylistScreen(sessionId: sessionId),
          ),
        ),
      );
    } else {
      added = await Navigator.of(context).pushNamed('/playlist/pick', arguments: sessionId);
    }
    if (added == true && mounted) await _refreshSession();
  }

  Future<void> _rateTrack(Map<String, dynamic> track, int rating) async {
    final trackId = track['id'] as String?;
    if (trackId == null) return;

    final myUserId = context.read<AuthProvider>().user?.id;
    final previous = _myRating(track, myUserId);
    final next = previous == rating ? 0 : rating;
    if (next == 0) return;

    _applyRatingLocally(track, myUserId, next);

    try {
      await context.read<SessionProvider>().rateTrack(trackId, next);
    } catch (err) {
      if (!mounted) return;
      _applyRatingLocally(track, myUserId, previous);
      showError(context, err);
    }
  }

  int? _myRating(Map<String, dynamic> track, String? myUserId) {
    if (myUserId == null) return null;
    final ratings = (track['ratings'] as List?)?.whereType<Map>() ?? const <Map>[];
    for (final r in ratings) {
      if (r['userId'] == myUserId) return (r['rating'] as num?)?.toInt();
    }
    return null;
  }

  void _applyRatingLocally(Map<String, dynamic> track, String? myUserId, int? rating) {
    if (myUserId == null) return;
    setState(() {
      final ratings = (track['ratings'] as List?)?.toList() ?? <dynamic>[];
      ratings.removeWhere((r) => r is Map && r['userId'] == myUserId);
      if (rating != null && rating != 0) {
        ratings.add({'userId': myUserId, 'rating': rating});
      }
      track['ratings'] = ratings;
    });
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.members,
    required this.onlineUserIds,
    required this.trackCount,
    required this.waitingForOthers,
  });

  final List<Map> members;
  final Set<String> onlineUserIds;
  final int trackCount;
  final bool waitingForOthers;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final accepted = members.where((m) => m['status'] == 'accepted').toList();

    // Фазу считает провайдер — он один видит и режим сессии, и паузу, и
    // подстройку. Экран лишь добавляет то, чего провайдер знать не может:
    // что второй участник ещё не в сети.
    final phase = context.select<PlaybackProvider, SyncPhase>((pb) => pb.syncPhase);
    final shown = waitingForOthers && phase == SyncPhase.synced
        ? SyncPhase.waiting
        : phase;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Знак и подпись под ним — единственное место экрана, где состояние
          // синхронизации видно целиком. Раньше о нём можно было догадываться
          // только по тому, совпадает ли музыка в наушниках.
          Center(
            child: Column(
              children: [
                SyncMark(state: shown, size: 76),
                const SizedBox(height: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: AppMotion.short,
                  child: Text(
                    _labelFor(shown),
                    key: ValueKey(shown),
                    style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (final member in accepted) ...[
                _MemberChip(
                  member: member,
                  isOnline: onlineUserIds.contains(member['userId']),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.queue_music_rounded, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Text(
                trackCount == 0 ? 'Пока без треков' : '$trackCount в очереди',
                style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Подпись под знаком.
  ///
  /// Называет то, что человек видит, а не то, как устроен механизм: не
  /// «якорь установлен», а «звучит одновременно».
  static String _labelFor(SyncPhase phase) => switch (phase) {
        SyncPhase.idle => 'Сессия не запущена',
        SyncPhase.waiting => 'Ждём второго',
        SyncPhase.synced => 'Звучит одновременно',
        SyncPhase.drifting => 'Подстраиваемся',
      };
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.member, required this.isOnline});

  final Map member;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final user = member['user'] as Map?;
    final name = user?['username'] as String? ?? 'Участник';
    final avatarUrl = (user?['spotifyUser'] as Map?)?['avatarUrl'] as String?;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.sm + 4, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              TappableAvatar(
                imageUrl: avatarUrl,
                radius: 16,
                title: name,
                heroTag: 'member-${member['userId']}',
              ),
              if (isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.brand.online,
                      border: Border.all(color: colors.surfaceContainerLow, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(name, style: texts.labelLarge),
        ],
      ),
    );
  }
}

class _EmptyTracksView extends StatelessWidget {
  const _EmptyTracksView({required this.onAddTracks});

  final VoidCallback onAddTracks;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.library_music_outlined,
      title: 'Очередь пуста',
      message: 'Добавьте треки из своих плейлистов — их услышат все участники.',
      actionLabel: 'Добавить треки',
      onAction: onAddTracks,
    );
  }
}

class _SessionTrackTile extends StatelessWidget {
  const _SessionTrackTile({
    required this.track,
    required this.index,
    required this.myUserId,
    required this.onPlay,
    required this.onRate,
  });

  final Map<String, dynamic> track;
  final int index;
  final String? myUserId;
  final VoidCallback onPlay;
  final void Function(int rating) onRate;

  int? get _myRating {
    if (myUserId == null) return null;
    final ratings = (track['ratings'] as List?)?.whereType<Map>() ?? const <Map>[];
    for (final r in ratings) {
      if (r['userId'] == myUserId) return (r['rating'] as num?)?.toInt();
    }
    return null;
  }

  /// Оценил ли трек кто-то ещё, кроме нас.
  bool get _ratedByOther {
    final ratings = (track['ratings'] as List?)?.whereType<Map>() ?? const <Map>[];
    return ratings.any((r) => r['userId'] != myUserId);
  }

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PlaybackProvider>();
    final myRating = _myRating;

    final uri = track['spotifyUri'] as String? ?? track['uri'] as String?;
    final isActive = pb.currentTrack?['uri'] == uri;

    return TrackCard(
      id: track['id'] as String? ?? '$index',
      title: track['trackName'] as String? ?? track['title'] as String? ?? '',
      artist: track['artistName'] as String? ?? track['artist'] as String? ?? '',
      artworkUrl: track['imageUrl'] as String?,
      durationMs: (track['durationMs'] as num?)?.toInt(),
      isActive: isActive,
      onPlay: onPlay,
      showLike: false,
      showMore: false,
      trailing: _RatingButtons(
        myRating: myRating,
        ratedByOther: _ratedByOther,
        onRate: onRate,
      ),
    );
  }
}

class _RatingButtons extends StatelessWidget {
  const _RatingButtons({
    required this.myRating,
    required this.ratedByOther,
    required this.onRate,
  });

  final int? myRating;
  final bool ratedByOther;
  final void Function(int rating) onRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ratedByOther)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Tooltip(
              message: 'Второй участник уже оценил',
              child: Icon(Icons.circle, size: 7, color: colors.onSurfaceVariant),
            ),
          ),
        _RatingButton(
          icon: Icons.thumb_down_outlined,
          activeIcon: Icons.thumb_down_rounded,
          isActive: myRating == -1,
          activeColor: colors.error,
          tooltip: 'Не нравится',
          onPressed: () => onRate(-1),
        ),
        _RatingButton(
          icon: Icons.thumb_up_outlined,
          activeIcon: Icons.thumb_up_rounded,
          isActive: myRating == 1,
          activeColor: colors.primary,
          tooltip: 'Нравится',
          onPressed: () => onRate(1),
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.activeColor,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: AnimatedSwitcher(
        duration: AppMotion.short,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: AppMotion.enter),
          child: child,
        ),
        child: Icon(
          isActive ? activeIcon : icon,
          key: ValueKey(isActive),
          size: 20,
          color: isActive ? activeColor : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}