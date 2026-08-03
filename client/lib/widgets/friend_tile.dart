import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../theme.dart';
import 'tappable_avatar.dart';

class FriendTile extends StatelessWidget {
  const FriendTile({
    super.key,
    required this.friend,
    required this.onViewProfile,
    required this.onRemoveFriend,
  });

  final Friend friend;
  final VoidCallback onViewProfile;
  final VoidCallback onRemoveFriend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: AppRadius.large,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onViewProfile,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 4,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              _AvatarWithPresence(friend: friend),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      friend.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    _PresenceLabel(friend: friend),
                  ],
                ),
              ),
              PopupMenuButton<_FriendAction>(
                icon: Icon(Icons.more_vert_rounded, color: colors.onSurfaceVariant),
                tooltip: 'Действия',
                shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
                onSelected: (action) => switch (action) {
                  _FriendAction.profile => onViewProfile(),
                  _FriendAction.remove => onRemoveFriend(),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _FriendAction.profile,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline_rounded),
                      title: Text('Открыть профиль'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _FriendAction.remove,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_remove_outlined, color: colors.error),
                      title: Text(
                        'Удалить из друзей',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FriendAction { profile, remove }

class _AvatarWithPresence extends StatelessWidget {
  const _AvatarWithPresence({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showOnline = friend.showsPresence && friend.isOnline;

    return Stack(
      children: [
        TappableAvatar(
          imageUrl: friend.avatarUrl,
          radius: 24,
          title: friend.name,
          heroTag: 'friend-${friend.id}',
        ),
        if (showOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.brand.online,
                border: Border.all(color: colors.surfaceContainerLow, width: 2.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _PresenceLabel extends StatelessWidget {
  const _PresenceLabel({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    if (!friend.showsPresence) return const SizedBox.shrink();

    if (friend.isOnline) {
      return Text(
        'В сети',
        style: texts.bodySmall?.copyWith(
          color: context.brand.online,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final lastSeen = friend.lastSeenAt;

    if (lastSeen == null) {
      return Text(
        'Не в сети',
        style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      );
    }

    return Text(
      'Был(а) в сети ${_formatLastSeen(lastSeen)}',
      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);

    if (diff.isNegative || diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return '${diff.inHours} ч. назад';
    if (diff.inDays < 7) return '${diff.inDays} д. назад';
    return 'давно';
  }
}