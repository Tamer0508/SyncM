import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../theme.dart';
import 'app_menu.dart';
import 'tappable_avatar.dart';

class FriendTile extends StatefulWidget {
  const FriendTile({
    super.key,
    required this.friend,
    required this.onViewProfile,
    required this.onRemoveFriend,
    this.onBlock,
  });

  final Friend friend;
  final VoidCallback onViewProfile;
  final VoidCallback onRemoveFriend;

  final VoidCallback? onBlock;

  @override
  State<FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends State<FriendTile> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final friend = widget.friend;

    final Color background;
    if (_pressed) {
      background = colors.surfaceContainerHigh;
    } else if (_hovered) {
      background = colors.surfaceContainerLow;
    } else {
      background = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed && !context.reduceMotion ? 0.99 : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.enter,
        child: Material(
          color: background,
          animationDuration: AppMotion.press,
          borderRadius: BorderRadius.circular(AppRadius.row),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onViewProfile,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 4,
            vertical: AppSpacing.xs + 2,
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
              AppMenuButton<_FriendAction>(
                iconColor: colors.onSurfaceVariant,
                tooltip: 'Действия',
                onSelected: (action) => switch (action) {
                  _FriendAction.profile => widget.onViewProfile(),
                  _FriendAction.remove => widget.onRemoveFriend(),
                  _FriendAction.block => widget.onBlock?.call(),
                },
                entries: [
                  const AppMenuEntry(
                    value: _FriendAction.profile,
                    icon: Icons.person_outline_rounded,
                    label: 'Открыть профиль',
                  ),
                  if (widget.onBlock != null)
                    const AppMenuEntry(
                      value: _FriendAction.block,
                      icon: Icons.block_rounded,
                      label: 'Заблокировать',
                      danger: true,
                    ),
                  const AppMenuEntry(
                    value: _FriendAction.remove,
                    icon: Icons.person_remove_outlined,
                    label: 'Удалить из друзей',
                    danger: true,
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

enum _FriendAction { profile, remove, block }

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
          radius: 21,
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