import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/animated_notification_button.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/friend_tile.dart';
import '../../widgets/empty_state.dart';
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

  Future<void> _blockFriend(Friend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.block_rounded, color: ctx.colors.error),
        title: Text('Заблокировать ${friend.name}?'),
        content: const Text(
          'Он не найдёт вас в поиске, не сможет отправить заявку или позвать '
          'в сессию. Дружба будет удалена. Уведомления он не получит.',
        ),
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
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final ok = await context.read<AuthProvider>().api.blockUser(friend.id);
      if (!mounted) return;

      if (ok) {
        context.read<FriendsProvider>().fetchFriends(refresh: true).ignore();
        showSuccess(context, '${friend.name} заблокирован');
      } else {
        showError(context, 'Не удалось заблокировать', force: true);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
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

    // Свои кнопки нужны там, где их не даёт оболочка.
    //
    // В широкой раскладке действия друзей стоят в шапке центральной панели —
    // второй такой же ряд был бы дублем. В узкой шапка показывает только
    // название раздела, и кнопки рисует сам экран.
    //
    // Раньше здесь было собственное измерение окна (< 900), не совпадавшее с
    // тем, по которому появляется шапка: в промежутке кнопки двоились.
    final needsOwnActions = !context.isWideWindow;

    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    Widget content;
    if (prov.friendsLoading && prov.friends.isEmpty) {
      content = const SizedBox.expand(
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: SkeletonList(itemCount: 6),
        ),
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
        onBlockFriend: _blockFriend,
      );
    }

    final body = AnimatedSwitcher(
      duration: AppMotion.short,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
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
      if (!needsOwnActions) return body;
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
    return EmptyState(
      icon: Icons.people_outline_rounded,
      title: 'Добавьте друзей',
      message: 'С другом можно слушать музыку одновременно — где бы вы ни были.',
      actionLabel: 'Найти друзей',
      onAction: onFindFriends,
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
    required this.onBlockFriend,
  });

  final List<Friend> friends;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final void Function(Friend friend) onViewProfile;
  final void Function(Friend friend) onRemoveFriend;
  final void Function(Friend friend) onBlockFriend;

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
      separatorBuilder: (_, _) => const SizedBox(height: 3),
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
          onBlock: () => onBlockFriend(friend),
        );
      },
    );
  }
}