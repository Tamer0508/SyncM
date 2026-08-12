import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../providers/friends_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/animated_notification_button.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/friend_tile.dart';
import '../../widgets/skeleton.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    this.embedded = false,
    this.onFindFriends,
    this.onOpenProfile,
  });

  final bool embedded;

  final VoidCallback? onFindFriends;

  final void Function(Map<String, dynamic> args)? onOpenProfile;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  void _openSearch() {
    final custom = widget.onFindFriends;
    if (custom != null) {
      custom();
      return;
    }
    Navigator.of(context).pushNamed('/friends/search');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<FriendsProvider>();
      prov.fetchFriends(refresh: true);
      prov.fetchIncomingRequests(refresh: true);
    });
  }

  Future<bool> _confirmRemove(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.person_remove_rounded, color: ctx.colors.error),
        title: const Text('Удалить из друзей?'),
        content: Text('$name пропадёт из вашего списка друзей.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _removeFriend(Friend friend) async {
    if (!await _confirmRemove(friend.name)) return;
    if (!mounted) return;

    final prov = context.read<FriendsProvider>();
    try {
      final removed = await prov.removeFriendByUserId(friend.id);
      if (!mounted) return;

      if (removed) {
        showSuccess(context, '${friend.name} удалён из друзей');
      } else {
        showError(context, 'Не удалось удалить друга', force: true);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  void _openProfile(Friend friend) {
    final args = {'name': friend.name, 'friendId': friend.id};

    final custom = widget.onOpenProfile;
    if (custom != null) {
      custom(args);
      return;
    }
    Navigator.of(context).pushNamed('/profile', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<FriendsProvider>();
    final isCompact = MediaQuery.sizeOf(context).width < 900;

    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    Widget content;
    if (prov.friendsLoading && prov.friends.isEmpty) {
      content = const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: SkeletonList(itemCount: 6),
      );
    } else if (prov.friends.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [const SizedBox(height: 60), _EmptyFriendsView(onFindFriends: _openSearch)],
      );
    } else {
      content = _FriendsListView(
        friends: prov.friends,
        hasMore: prov.hasMoreFriends,
        isLoadingMore: prov.friendsLoading,
        onLoadMore: prov.fetchFriends,
        onViewProfile: _openProfile,
        onRemoveFriend: _removeFriend,
      );
    }

    final body = AnimatedSwitcher(
      duration: AppMotion.short,
      child: enablePullToRefresh
          ? RefreshIndicator(onRefresh: prov.refreshFriends, child: content)
          : content,
    );

    final actions = [
      AppIconButton(
        icon: Icons.person_add_alt_1_rounded,
        onPressed: _openSearch,
        tooltip: 'Найти друзей',
      ),
      AnimatedNotificationButton(
        icon: Icons.mail_outline_rounded,
        activeIcon: Icons.mark_email_unread_rounded,
        count: prov.unreadCount,
        tooltip: 'Заявки в друзья',
        onPressed: () => Navigator.of(context).pushNamed('/friends/requests'),
      ),
      const SizedBox(width: AppSpacing.xs),
    ];

    if (widget.embedded) {
      if (!isCompact) return body;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Друзья'), actions: actions),
      body: body,
      floatingActionButton: prov.friends.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _openSearch,
              tooltip: 'Найти друзей',
              child: const Icon(Icons.person_add_rounded),
            ),
    );
  }
}

class _EmptyFriendsView extends StatelessWidget {
  const _EmptyFriendsView({required this.onFindFriends});

  final VoidCallback onFindFriends;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 88,
            color: colors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Пока никого нет',
            style: texts.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Найдите друзей, чтобы вместе слушать музыку в общих сессиях.',
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onFindFriends,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Найти друзей'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(220, 52),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendsListView extends StatelessWidget {
  const _FriendsListView({
    required this.friends,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onViewProfile,
    required this.onRemoveFriend,
  });

  final List<Friend> friends;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final void Function(Friend friend) onViewProfile;
  final void Function(Friend friend) onRemoveFriend;

  @override
  Widget build(BuildContext context) {
    final showFooter = hasMore || isLoadingMore;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      itemCount: friends.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        if (i >= friends.length) {
          if (isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: OutlinedButton(
              onPressed: onLoadMore,
              child: const Text('Загрузить ещё'),
            ),
          );
        }

        final friend = friends[i];
        return FriendTile(
          friend: friend,
          onViewProfile: () => onViewProfile(friend),
          onRemoveFriend: () => onRemoveFriend(friend),
        );
      },
    );
  }
}