import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncm/services/api_service.dart';
import '../../providers/friends_provider.dart';
import '../../widgets/friend_tile.dart';
import '../../utils/notifications.dart';
  
class FriendsScreen extends StatefulWidget {
  final bool embedded;
  const FriendsScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      prov.markAsRead();
      prov.fetchFriends(refresh: true);
    });
  }

  Future<bool> _confirmRemove(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердите удаление'),
        content: Text('Удалить пользователя "$name" из друзей?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<FriendsProvider>(context);
    final isMobile = MediaQuery.of(context).size.width < 900;   // ← ключевая проверка

    Widget bodyContent = prov.friends.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('У вас пока нет друзей',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(
                    'Нажмите на кнопку ниже, чтобы найти людей и начать общение.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.78)),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/friends/search'),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Найти друзей'),
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: prov.friends.length + (prov.hasMoreFriends ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i >= prov.friends.length) {
                if (prov.friendsLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: TextButton(
                    onPressed: () => prov.fetchFriends(),
                    child: const Text('Загрузить ещё'),
                  ),
                );
              }
              final f = prov.friends[i];
              return FriendTile(
                friend: f,
                onViewProfile: () => Navigator.of(context).pushNamed(
                  '/profile',
                  arguments: {'name': f.name, 'friendId': f.id},
                ),
                onRemoveFriend: () async {
                  final shouldDelete = await _confirmRemove(context, f.name);
                  if (!shouldDelete) return;

                  final prov =
                      Provider.of<FriendsProvider>(context, listen: false);

                  String? friendshipId = f.friendshipId;
                  if (friendshipId == null) {
                    try {
                      await prov.fetchFriends(refresh: true);
                      final matches = prov.friends
                          .where((x) => x.id == f.id)
                          .toList();
                      if (matches.isNotEmpty) {
                        friendshipId = matches.first.friendshipId;
                      }
                    } catch (e) {
                      showAppNotification(context, message: 'Ошибка обновления списка: $e', type: NotificationType.error);

                      return;
                    }
                  }

                  if (friendshipId == null) {
                    showAppNotification(context, message: 'Ошибка: идентификатор связи отсутствует. Обновите список и повторите попытку.'
                    , type: NotificationType.error);
                    return;
                  }

                  try {
                    final success = await prov.removeFriend(friendshipId);
                    if (success) {
                      showAppNotification(context, message: 'Друг удалён', type: NotificationType.success);
                    } else {
                      showAppNotification(context, message: 'Не удалось удалить друга', type: NotificationType.error);
                    }
                  } catch (e) {
                    final msg = (e is ApiException)
                        ? e.userMessage
                        : 'Ошибка удаления: $e';
                    showAppNotification(context, message: msg, type: NotificationType.error);
                  }
                },
              );
            },
          );

    if (widget.embedded && isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Друзья'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/friends/search'),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/friends/requests'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async => await prov.fetchFriends(refresh: true),
            ),
          ],
        ),
        body: bodyContent,
      );
    }

    if (widget.embedded) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () =>
                Navigator.of(context).pushNamed('/friends/search'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () =>
                Navigator.of(context).pushNamed('/friends/requests'),
          ),
          IconButton(
            onPressed: () async {
              await prov.fetchFriends(refresh: true);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: bodyContent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}