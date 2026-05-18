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

  Widget _buildSubtitle(BuildContext context) {
    final theme = Theme.of(context);
    if (friend.isOnlineHidden) {
      return const SizedBox.shrink();
    }
    if (friend.isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 6),
          Text('В сети', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
        ],
      );
    } else if (friend.lastSeenAt != null) {
      final diff = DateTime.now().difference(friend.lastSeenAt!);
      String text;
      if (diff.inMinutes < 1) {
        text = 'Только что';
      } else if (diff.inMinutes < 60) {
        text = '${diff.inMinutes} мин. назад';
      } else if (diff.inHours < 24) {
        text = '${diff.inHours} ч. назад';
      } else {
        text = '${diff.inDays} д. назад';
      }
      return Text('Был(а) в сети $text', style: theme.textTheme.bodySmall);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tileColor: theme.cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      onTap: onViewProfile,
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
      subtitle: _buildSubtitle(context),
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