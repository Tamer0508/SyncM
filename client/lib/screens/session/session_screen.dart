import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/playback_provider.dart';
import '../../utils/notifications.dart';

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
        pb.initSocket(_session!['id'], auth.user?.id ?? '');
      }
    }
  }

  Future<void> _refreshSession() async {
    setState(() => _refreshing = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final sessions = await api.getMySessions();
      final updated = (sessions as List)
          .firstWhere((s) => s['id'] == _session!['id'], orElse: () => null);
      if (updated != null && mounted)
        setState(() => _session = Map<String, dynamic>.from(updated));
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
                if (result == true && mounted) _refreshSession();
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
          ...List.generate(tracks.length, (i) {
            final t = tracks[i];
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                    color: theme.cardColor,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: t['imageUrl'] != null
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
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(t['artistName'] ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
