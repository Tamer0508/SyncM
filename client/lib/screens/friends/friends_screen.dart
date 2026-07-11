import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncm/services/api_service.dart';
import '../../providers/friends_provider.dart';
import '../../widgets/friend_tile.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';

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
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.person_remove, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Text('Подтвердите удаление',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Text(
            'Удалить "$name" из друзей? Это действие нельзя отменить.',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<FriendsProvider>(context);
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 900;

    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    Widget buildFriendsList() {
      return _FriendsListView(
        friends: prov.friends,
        hasMore: prov.hasMoreFriends,
        onLoadMore: () => prov.fetchFriends(),
        isLoadingMore: prov.friendsLoading,
        onViewProfile: (f) => Navigator.of(context).pushNamed(
          '/profile',
          arguments: {'name': f.name, 'friendId': f.id},
        ),
        onRemoveFriend: (f) async {
          final shouldDelete = await _confirmRemove(context, f.name);
          if (!shouldDelete) return;

          final prov = Provider.of<FriendsProvider>(context, listen: false);
          String? friendshipId = f.friendshipId;
          if (friendshipId == null) {
            try {
              await prov.fetchFriends(refresh: true);
              final matches = prov.friends.where((x) => x.id == f.id).toList();
              if (matches.isNotEmpty) {
                friendshipId = matches.first.friendshipId;
              }
            } catch (e) {
              showAppNotification(context,
                  message: 'Ошибка обновления списка: $e',
                  type: NotificationType.error);
              return;
            }
          }
          if (friendshipId == null) {
            showAppNotification(context,
                message: 'Ошибка: идентификатор связи отсутствует. Обновите список и повторите попытку.',
                type: NotificationType.error);
            return;
          }
          try {
            final success = await prov.removeFriend(friendshipId);
            if (success) {
              showAppNotification(context,
                  message: 'Друг удалён', type: NotificationType.success);
            } else {
              showAppNotification(context,
                  message: 'Не удалось удалить друга', type: NotificationType.error);
            }
          } catch (e) {
            final msg = (e is ApiException) ? e.userMessage : 'Ошибка удаления: $e';
            showAppNotification(context, message: msg, type: NotificationType.error);
          }
        },
      );
    }

    // Анимированное переключение состояний (загрузка / пусто / список)
    Widget bodyContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: prov.friendsLoading && prov.friends.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : prov.friends.isEmpty
              ? _EmptyFriendsView()
              : enablePullToRefresh
                  ? RefreshIndicator(
                      onRefresh: prov.refreshFriends,
                      child: buildFriendsList(),
                    )
                  : buildFriendsList(),
    );

    final appBarActions = [
      AppIconButton(
        icon: Icons.person_add_alt_1,
        onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
        tooltip: 'Поиск друзей',
      ),
      AppIconButton(
        icon: Icons.notifications_none,
        onPressed: () => Navigator.of(context).pushNamed('/friends/requests'),
        tooltip: 'Запросы',
      ),
      AppIconButton(
        icon: Icons.refresh,
        onPressed: () async => await prov.fetchFriends(refresh: true),
        tooltip: 'Обновить',
      ),
    ];

    if (widget.embedded && isMobile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Друзья'), actions: appBarActions),
        body: bodyContent,
      );
    }

    if (widget.embedded) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Друзья'), actions: appBarActions),
      body: bodyContent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
        icon: const Icon(Icons.person_add),
        label: const Text('Найти друзей'),
        elevation: 4,
      ),
    );
  }
}

class _EmptyFriendsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 96, color: theme.colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 24),
            Text('У вас пока нет друзей',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Нажмите на кнопку ниже, чтобы найти людей и начать общение.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.78)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
              icon: const Icon(Icons.person_add),
              label: const Text('Найти друзей'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendsListView extends StatelessWidget {
  final List<dynamic> friends;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final bool isLoadingMore;
  final Function(dynamic) onViewProfile;
  final Function(dynamic) onRemoveFriend;

  const _FriendsListView({
    Key? key,
    required this.friends,
    required this.hasMore,
    required this.onLoadMore,
    required this.isLoadingMore,
    required this.onViewProfile,
    required this.onRemoveFriend,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: friends.length + (hasMore || isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i >= friends.length) {
          if (isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: onLoadMore,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Загрузить ещё'),
            ),
          );
        }
        final f = friends[i];
        return FriendTile(
          friend: f,
          onViewProfile: () => onViewProfile(f),
          onRemoveFriend: () => onRemoveFriend(f),
        );
      },
    );
  }
}