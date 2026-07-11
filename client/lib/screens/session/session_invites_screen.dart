import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';

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
    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    Widget buildContent(SessionProvider prov) {
      final isLoading = prov.invitesLoading && prov.invites.isEmpty;
      final isEmpty = prov.invites.isEmpty && !prov.invitesLoading;

      if (isLoading) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - kToolbarHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
        );
      }

      if (isEmpty) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - kToolbarHeight,
            child: _EmptyInvitesView(theme: theme),
          ),
        );
      }

      return _InvitesList(
        theme: theme,
        invites: prov.invites as List<Map<String, dynamic>>,
        hostNameForInvite: prov.hostNameForInvite,
        responding: _responding,
        onAccept: (id) => _respond(id, true),
        onDecline: (id) => _respond(id, false),
      );
    }

    final child = Consumer<SessionProvider>(
      builder: (context, prov, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: buildContent(prov),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашения в сессии'),
        actions: [
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Обновить',
            onPressed: () => Provider.of<SessionProvider>(context, listen: false)
                .fetchInvites(refresh: true),
          ),
        ],
      ),
      body: enablePullToRefresh
          ? RefreshIndicator(
              onRefresh: () => Provider.of<SessionProvider>(context, listen: false)
                  .fetchInvites(refresh: true),
              child: child,
            )
          : child,
    );
  }
}

class _EmptyInvitesView extends StatelessWidget {
  final ThemeData theme;
  const _EmptyInvitesView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline, size: 80, color: theme.colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 24),
            Text('Приглашений нет',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Когда друг пригласит вас в сессию, уведомление появится здесь.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitesList extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> invites;
  final String? Function(Map<String, dynamic>) hostNameForInvite;
  final Set<String> responding;
  final Function(String) onAccept;
  final Function(String) onDecline;

  const _InvitesList({
    required this.theme,
    required this.invites,
    required this.hostNameForInvite,
    required this.responding,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: invites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final invite = invites[i];
        final sessionId = invite['id'] as String;
        final name = invite['name'] as String? ?? 'Сессия';
        final hostName = hostNameForInvite(invite) ?? 'Друг';
        final isResponding = responding.contains(sessionId);

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          color: theme.cardColor,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.music_note, size: 24, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Приглашение от $hostName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isResponding ? null : () => onDecline(sessionId),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Отклонить'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isResponding ? null : () => onAccept(sessionId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: isResponding
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
  }
}