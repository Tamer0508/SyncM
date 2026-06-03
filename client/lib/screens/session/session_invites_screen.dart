import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/notifications.dart';

class SessionInvitesScreen extends StatefulWidget {
  const SessionInvitesScreen({Key? key}) : super(key: key);

  @override
  State<SessionInvitesScreen> createState() => _SessionInvitesScreenState();
}

class _SessionInvitesScreenState extends State<SessionInvitesScreen> {
  final Set<String> _responding = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<SessionProvider>(context, listen: false);
      prov.markInvitesAsRead();
      prov.fetchInvites(refresh: true);
    });
  }

  Future<void> _respond(String sessionId, bool accept) async {
    if (_responding.contains(sessionId)) return;
    setState(() => _responding.add(sessionId));
    try {
      final prov = Provider.of<SessionProvider>(context, listen: false);
      final result = await prov.respondToInvite(sessionId, accept);
      if (!mounted) return;
      if (result == null) {
        showAppNotification(
          context,
          message: 'Не удалось ответить на приглашение',
          type: NotificationType.error,
        );
        return;
      }
      if (accept) {
        final session = result['session'] as Map<String, dynamic>?;
        if (session != null) {
          Navigator.of(context).pushReplacementNamed('/session', arguments: session);
        }
      } else {
        showAppNotification(context, message: 'Приглашение отклонено');
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, message: 'Ошибка: $e', type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _responding.remove(sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашения в сессии'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<SessionProvider>(context, listen: false).fetchInvites(refresh: true),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Consumer<SessionProvider>(
          builder: (context, prov, _) {
            if (prov.invitesLoading && prov.invites.isEmpty) {
              return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
            }
            if (prov.invites.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_off, size: 64, color: theme.colorScheme.primary.withOpacity(0.8)),
                    const SizedBox(height: 16),
                    Text('Приглашений нет', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Когда друг пригласит вас в сессию, уведомление появится здесь.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: prov.invites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) {
                final invite = prov.invites[i];
                final sessionId = invite['id'] as String;
                final name = invite['name'] as String? ?? 'Сессия';
                final hostName = prov.hostNameForInvite(invite) ?? 'Друг';
                final isResponding = _responding.contains(sessionId);

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('От: $hostName', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isResponding ? null : () => _respond(sessionId, false),
                                child: const Text('Отклонить'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isResponding ? null : () => _respond(sessionId, true),
                                child: isResponding
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Принять'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
