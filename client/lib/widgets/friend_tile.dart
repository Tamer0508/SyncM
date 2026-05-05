import 'package:flutter/material.dart';
import '../models/friend.dart';

class FriendTile extends StatelessWidget {
  final Friend friend;
  final VoidCallback onViewProfile;
  final VoidCallback onRemoveFriend;

  const FriendTile({
    Key? key,
    required this.friend,
    required this.onViewProfile,
    required this.onRemoveFriend,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tileColor: theme.cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
            ? NetworkImage(friend.avatarUrl!)
            : null,
        backgroundColor: theme.colorScheme.surfaceVariant,
        child: friend.avatarUrl == null || friend.avatarUrl!.isEmpty
            ? Icon(Icons.person, color: theme.colorScheme.primary)
            : null,
      ),
      title: Text(
        friend.name,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Online',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '',
        elevation: 4,
        icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
        onSelected: (value) {
          if (value == 'profile') {
            onViewProfile();
          } else if (value == 'remove') {
            onRemoveFriend();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'profile',
            child: Row(
              children: [
                Icon(Icons.person, color: theme.iconTheme.color),
                const SizedBox(width: 8),
                const Text('Посмотреть профиль'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.remove_circle, color: theme.iconTheme.color),
                const SizedBox(width: 8),
                const Text('Удалить из друзей'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
