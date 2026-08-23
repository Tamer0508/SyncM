import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/animated_notification_button.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/friend_tile.dart';
import '../../widgets/screen_chrome.dart';
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

  Future<bool> _confirmRemove(String name) {
    return showConfirmDialog(
      context,
      icon: Icons.person_remove_rounded,
      title: L.of(context).friendsRemoveTitle,
      message: L.of(context).friendsRemoveMessage(name),
      confirmLabel: L.of(context).commonDelete,
    );
  }

  Future<void> _blockFriend(Friend friend) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.block_rounded,
      title: L.of(context).friendsBlockTitle(friend.name),
      message: L.of(context).friendsBlockMessage,
      confirmLabel: L.of(context).friendBlock,
    );

    if (!confirmed || !mounted) return;

    try {
      final ok = await context.read<AuthProvider>().api.blockUser(friend.id);
      if (!mounted) return;

      if (ok) {
        context.read<FriendsProvider>().fetchFriends(refresh: true).ignore();
        showSuccess(context, L.of(context).friendsBlocked(friend.name));
      } else {
        showError(context, L.of(context).friendsBlockFailed, force: true);
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
        showSuccess(context, L.of(context).friendsRemoved(friend.name));
      } else {
        showError(context, L.of(context).friendsRemoveFailed, force: true);
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
        tooltip: L.of(context).navFindFriends,
      ),
      AnimatedNotificationButton(
        icon: Icons.mail_outline_rounded,
        activeIcon: Icons.mark_email_unread_rounded,
        count: prov.unreadCount,
        tooltip: L.of(context).homeFriendRequests,
        onPressed: () => Navigator.of(context).pushNamed('/friends/requests'),
      ),
    ];

    if (widget.embedded) {
      if (!needsOwnActions) return body;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ),
          Expanded(child: body),
        ],
      );
    }

    return ScreenChrome(
      header: ScreenHeader(
        title: L.of(context).commonFriends,
        onBack: () => Navigator.of(context).pop(),
        actions: actions,
      ),
      child: body,
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
      title: L.of(context).friendsEmptyTitle,
      message: L.of(context).friendsEmptyMessage,
      actionLabel: L.of(context).navFindFriends,
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
              child: Text(L.of(context).commonLoadMore),
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