import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../widgets/friend_tile.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({Key? key}) : super(key: key);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.of(context).pushNamed('/friends/requests'),
          ),
          IconButton(
            onPressed: () async {
              await prov.fetchFriends();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: prov.friends.isEmpty
          ? const Center(child: Text('Нет друзей. Нажмите обновить.'))
          : ListView.builder(
              itemCount: prov.friends.length,
              itemBuilder: (_, i) {
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

                    final prov = Provider.of<FriendsProvider>(context, listen: false);

                    // Если у записи нет friendshipId — попробуем обновить список и получить его
                    String? friendshipId = f.friendshipId;
                    if (friendshipId == null) {
                      try {
                        await prov.fetchFriends();
                        final matches = prov.friends.where((x) => x.id == f.id).toList();
                        if (matches.isNotEmpty) friendshipId = matches.first.friendshipId;
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка обновления списка: $e')),
                        );
                        return;
                      }
                    }

                    if (friendshipId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ошибка: идентификатор связи отсутствует. Обновите список и повторите попытку.')),
                      );
                      return;
                    }

                    // Показать индикатор прогресса
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final success = await prov.removeFriend(friendshipId);
                      Navigator.of(context).pop(); // закрыть индикатор

                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Друг удален')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Не удалось удалить друга')),
                        );
                      }
                    } catch (e) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка удаления: $e')),
                      );
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
