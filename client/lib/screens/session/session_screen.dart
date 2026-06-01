import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/playback_provider.dart';
import '../../utils/notifications.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({Key? key}) : super(key: key);

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? _session;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _session = args;
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final pb = Provider.of<PlaybackProvider>(context, listen: false);
        pb.initSocket(_session!['id'], auth.user?.id ?? '');
      }
    }
  }

  Future<void> _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить сессию?'),
        content: const Text('Сессия будет закрыта для всех участников.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final result = await Provider.of<SessionProvider>(context, listen: false)
          .endSession(_session!['id']);
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/session/results', arguments: result);
      }
    } catch (e) {
      if (mounted) showAppNotification(context, message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (_session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = (_session!['members'] as List? ?? []);
    final tracks = (_session!['tracks'] as List? ?? []);
    final isHost = _session!['hostId'] == auth.user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(_session!['name'] ?? 'Сессия'),
        actions: [
          if (isHost)
            TextButton.icon(
              onPressed: _endSession,
              icon: Icon(Icons.stop_circle, color: theme.colorScheme.error),
              label: Text('Завершить', style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Участники
            Text('Участники', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: members.map<Widget>((m) {
                final user = m['user'] as Map<String, dynamic>?;
                final avatarUrl = user?['spotifyUser']?['avatarUrl'] as String?;
                final name = user?['username'] as String? ?? '?';
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        backgroundColor: theme.colorScheme.surfaceVariant,
                        child: avatarUrl == null ? Text(name[0].toUpperCase()) : null,
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: theme.textTheme.bodySmall),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Треки
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Треки', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/playlist/pick', arguments: _session!['id']),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Text('Треки ещё не добавлены',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
                    )
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (_, i) {
                        final t = tracks[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          tileColor: theme.cardColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: t['imageUrl'] != null
                                ? Image.network(t['imageUrl'], width: 48, height: 48, fit: BoxFit.cover)
                                : Container(width: 48, height: 48, color: theme.colorScheme.surfaceVariant,
                                    child: const Icon(Icons.music_note)),
                          ),
                          title: Text(t['trackName'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text(t['artistName'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.thumb_up_outlined),
                                onPressed: () async {
                                  await Provider.of<SessionProvider>(context, listen: false)
                                      .rateTrack(t['id'], 1);
                                  showAppNotification(context, message: '👍 Понравилось!', type: NotificationType.success);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.thumb_down_outlined),
                                onPressed: () async {
                                  await Provider.of<SessionProvider>(context, listen: false)
                                      .rateTrack(t['id'], 0);
                                  showAppNotification(context, message: '👎 Не понравилось', type: NotificationType.success);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}