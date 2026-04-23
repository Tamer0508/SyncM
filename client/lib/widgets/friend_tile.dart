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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundImage: friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
            ? NetworkImage(friend.avatarUrl!)
            : null,
        backgroundColor: Colors.grey[700],
        child: friend.avatarUrl == null || friend.avatarUrl!.isEmpty
            ? const Icon(Icons.person, color: Colors.white)
            : null,
      ),
      title: Text(
        friend.name,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Online',
        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '',
        elevation: 2,
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
