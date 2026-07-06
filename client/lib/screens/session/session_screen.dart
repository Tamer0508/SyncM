import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/playback_provider.dart';
import '../../utils/notifications.dart';
import '../player/now_playing.dart';
import '../../services/socket_service.dart';

class SessionScreen extends StatefulWidget {
  final bool embedded;
  final Map<String, dynamic>? sessionData;
  final VoidCallback? onBack;

  const SessionScreen(
      {Key? key, this.embedded = false, this.sessionData, this.onBack})
      : super(key: key);

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? _session;
  bool _initialized = false;
  bool _refreshing = false;
  PlaybackProvider? _playback;
  SocketService? _sessionSocket; // Фаза 6: для отписки в dispose
  bool _isPlayerOpen = false;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  void _syncSessionQueue() {
    if (_session == null) return;
    final tracks = _session!['tracks'] as List? ?? [];
    Provider.of<PlaybackProvider>(context, listen: false).setSessionQueue(tracks);
  }

  void _openPlayerIfMobile(Map<String, dynamic> track) async {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    
    // Если мы на десктопе или плеер УЖЕ открыт — ничего не делаем
    if (isDesktop || !mounted || _isPlayerOpen) return;

    _isPlayerOpen = true;

    // Ждем, пока пользователь не закроет экран плеера
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NowPlayingScreen(
        title: track['title'] as String?,
        artist: track['artist'] as String?,
        artworkUrl: track['imageUrl'] as String?,
      ),
    ));

    // Как только экран закрылся (пользователь нажал "назад"), сбрасываем флаг
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

    await auth.api.logPlay(
      uri,
      track['title'] as String? ?? '',
      track['artist'] as String? ?? '',
    );

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
  pb.initSession(_session!['id'], auth.user?.id ?? '', socket, isHost: isHost);
  _setupPlaybackCallbacks();
  _setupSessionSocketListeners(socket);
  _syncSessionQueue();
}
    }
  }

  StreamSubscription<void>? _reconnectSub;

  // Фаза 6: реакция на события связности и участников сессии.
  void _setupSessionSocketListeners(SocketService socket) {
    _sessionSocket = socket;
    // Участник окончательно отпал (не переподключился за таймаут) — обновляем
    // список и уведомляем.
    socket.on('participant_dropped', (data) {
      if (!mounted) return;
      _refreshSession();
    });
    // Кто-то (пере)подключился к сессии — тоже обновим список участников.
    socket.on('user_joined', (data) {
      if (!mounted) return;
      _refreshSession();
    });
    // Наше соединение восстановилось после разрыва — обновим состояние сессии.
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
    _sessionSocket?.off('participant_dropped');
    _sessionSocket?.off('user_joined');
    super.dispose();
  }

  Future<void> _refreshSession() async {
    setState(() => _refreshing = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final sessions = await api.getMySessions();
      final updated = (sessions as List)
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

    try {
      final result = await Provider.of<SessionProvider>(context, listen: false)
          .endSession(_session!['id']);
      if (mounted) {
        if (widget.embedded && widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.of(context)
              .pushReplacementNamed('/session/results', arguments: result);
        }
      }
    } catch (e) {
      if (mounted)
        showAppNotification(context,
            message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (_session == null)
      return const Center(child: CircularProgressIndicator());

    final members = (_session!['members'] as List? ?? []);
    final tracks = (_session!['tracks'] as List? ?? []);
    final isHost = _session!['hostId'] == auth.user?.id;

    final body = RefreshIndicator(
      onRefresh: _refreshSession,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Участники (${members.length})',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
            height: 90,
            child: members.isEmpty
                ? Center(
                    child: Text('Пока нет участников',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.6))))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) {
                      final m = members[i];
                      final user = m['user'] as Map<String, dynamic>?;
                      final avatarUrl =
                          user?['spotifyUser']?['avatarUrl'] as String?;
                      final name = user?['username'] as String? ?? '?';
                      final isPending = m['status'] == 'pending';
                      final isHostUser = _session!['hostId'] == user?['id'];
                      return Column(children: [
                        Stack(children: [
                          CircleAvatar(
                              radius: 26,
                              backgroundImage: avatarUrl != null
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              backgroundColor: theme.colorScheme.surfaceVariant,
                              child: avatarUrl == null
                                  ? Text(name[0].toUpperCase(),
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              color: theme.colorScheme.primary))
                                  : null),
                          if (isHostUser)
                            Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                    decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.star,
                                        size: 14, color: Colors.white))),
                          if (isPending)
                            Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                    decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(Icons.hourglass_empty,
                                        size: 14,
                                        color: theme.colorScheme.primary))),
                        ]),
                        const SizedBox(height: 6),
                        SizedBox(
                            width: 72,
                            child: Text(name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: isHostUser
                                        ? FontWeight.w600
                                        : FontWeight.normal))),
                      ]);
                    })),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Треки (${tracks.length})',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          TextButton.icon(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .pushNamed('/playlist/pick', arguments: _session!['id']);
                if (result == true && mounted) await _refreshSession();
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Добавить')),
        ]),
        const SizedBox(height: 12),
        if (tracks.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: Text('Треки ещё не добавлены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.6)))))
        else
          Consumer<PlaybackProvider>(builder: (_, pb, __) {
            return Column(
              children: List.generate(tracks.length, (i) {
            final t = tracks[i];
            final uri = t['spotifyUri'] ?? t['uri'];
            final isPlaying = pb.sessionMode &&
                pb.isPlaying &&
                pb.currentTrack?['uri'] == uri;
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: isPlaying ? 2 : 0,
                    color: isPlaying
                        ? theme.colorScheme.primary.withOpacity(0.12)
                        : theme.cardColor,
                    child: ListTile(
                      onTap: () => _onTrackTap(
                          Map<String, dynamic>.from(t as Map), i),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: t['imageUrl'] != null &&
                                  (t['imageUrl'] as String).isNotEmpty
                              ? Image.network(t['imageUrl'],
                                  width: 48, height: 48, fit: BoxFit.cover)
                              : Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Icon(Icons.music_note,
                                      color: theme.colorScheme.primary))),
                      title: Text(t['trackName'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isPlaying ? theme.colorScheme.primary : null)),
                      subtitle: Text(t['artistName'] ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isPlaying)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.equalizer,
                                color: theme.colorScheme.primary, size: 20),
                          ),
                        IconButton(
                            icon: const Icon(Icons.thumb_up_outlined),
                            tooltip: 'Нравится',
                            onPressed: () async {
                              await Provider.of<SessionProvider>(context,
                                      listen: false)
                                  .rateTrack(t['id'], 1);
                              showAppNotification(context,
                                  message: '👍 Понравилось!',
                                  type: NotificationType.success);
                            }),
                        IconButton(
                            icon: const Icon(Icons.thumb_down_outlined),
                            tooltip: 'Не нравится',
                            onPressed: () async {
                              await Provider.of<SessionProvider>(context,
                                      listen: false)
                                  .rateTrack(t['id'], 0);
                              showAppNotification(context,
                                  message: '👎 Не понравилось',
                                  type: NotificationType.success);
                            }),
                      ]),
                    )));
              }),
            );
          }),
      ]),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(_session!['name'] ?? 'Сессия'), actions: [
        if (isHost)
          TextButton.icon(
              onPressed: _endSession,
              icon: Icon(Icons.stop_circle, color: theme.colorScheme.error),
              label: Text('Завершить',
                  style: TextStyle(color: theme.colorScheme.error)))
      ]),
      body: body,
    );
  }
}