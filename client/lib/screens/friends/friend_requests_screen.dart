import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/api_service.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({Key? key}) : super(key: key);

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      prov.fetchIncomingRequests(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Запросы в друзья'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final prov = Provider.of<FriendsProvider>(context, listen: false);
              prov.fetchIncomingRequests(refresh: true);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Consumer<FriendsProvider>(
          builder: (context, prov, _) {
            if (prov.incomingLoading && prov.incomingRequests.isEmpty) {
              return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
            }
            if (prov.incomingRequests.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mark_email_read, size: 64, color: theme.colorScheme.primary.withOpacity(0.8)),
                    const SizedBox(height: 16),
                    Text('Запросов нет', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Попросите друзей отправить вам запрос, чтобы начать общение.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.75)),
                        textAlign: TextAlign.center),
                  ],
                ),
              );
            } else {
              return ListView.separated(
                itemCount: prov.incomingRequests.length + (prov.hasMoreIncoming ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  if (i >= prov.incomingRequests.length) {
                    if (prov.incomingLoading) {
                      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                    }
                    return Center(
                      child: TextButton(
                        onPressed: () => prov.fetchIncomingRequests(),
                        child: const Text('Загрузить ещё'),
                      ),
                    );
                  }
                  final r = prov.incomingRequests[i];
                  final sender = r['sender'] as Map<String, dynamic>?;
                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundImage: sender?['avatarUrl'] != null
                              ? NetworkImage(sender!['avatarUrl'])
                              : null,
                          child: sender?['avatarUrl'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(sender?['displayName'] ?? 'Unknown',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text('Хочет добавить вас в друзья',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.78))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () async {
                                try {
                                  await prov.acceptRequest(r['id']);
                                } catch (e) {
                                  final msg = (e is ApiException)
                                      ? e.userMessage
                                      : 'Ошибка принятия заявки';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              },
                              icon: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                            ),
                            IconButton(
                              onPressed: () async {
                                try {
                                  await prov.deleteRequest(r['id']);
                                  prov.fetchIncomingRequests(refresh: true);
                                } catch (e) {
                                  final msg = (e is ApiException)
                                      ? e.userMessage
                                      : 'Ошибка отклонения заявки';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              },
                              icon: Icon(Icons.close, color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }
          },
        ),
      ),
    );
  }
}