import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/api_service.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';

class FriendRequestsScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onBack;

  const FriendRequestsScreen({Key? key, this.embedded = false, this.onBack})
      : super(key: key);

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<FriendsProvider>(context, listen: false);
      prov.markAsRead();
      prov.fetchIncomingRequests(refresh: true);
    });
  }

  Future<void> _acceptRequest(String requestId) async {
    if (_loadingIds.contains(requestId)) return;
    setState(() => _loadingIds.add(requestId));
    try {
      await Provider.of<FriendsProvider>(context, listen: false)
          .acceptRequest(requestId);
    } catch (e) {
      if (mounted) {
        final msg =
            (e is ApiException) ? e.userMessage : 'Ошибка принятия заявки';
        showAppNotification(context,
            message: msg, type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(requestId));
    }
  }

  Future<void> _declineRequest(String requestId) async {
    if (_loadingIds.contains(requestId)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.person_remove, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Text('Отклонить запрос?',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text(
              'Этот пользователь больше не сможет отправлять вам запросы.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Отклонить'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    setState(() => _loadingIds.add(requestId));
    try {
      await Provider.of<FriendsProvider>(context, listen: false)
          .deleteRequest(requestId);
      // Обновляем список
      Provider.of<FriendsProvider>(context, listen: false)
          .fetchIncomingRequests(refresh: true);
    } catch (e) {
      if (mounted) {
        final msg =
            (e is ApiException) ? e.userMessage : 'Ошибка отклонения заявки';
        showAppNotification(context,
            message: msg, type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = Consumer<FriendsProvider>(
      builder: (context, prov, _) {
        final isLoading =
            prov.incomingLoading && prov.incomingRequests.isEmpty;
        final isEmpty =
            prov.incomingRequests.isEmpty && !prov.incomingLoading;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : isEmpty
                  ? _EmptyRequestsView(theme: theme)
                  : _RequestsList(
                      theme: theme,
                      requests: prov.incomingRequests,
                      hasMore: prov.hasMoreIncoming,
                      isLoadingMore: prov.incomingLoading,
                      loadingIds: _loadingIds,
                      onLoadMore: () => prov.fetchIncomingRequests(),
                      onAccept: _acceptRequest,
                      onDecline: _declineRequest,
                    ),
        );
      },
    );

    // Встроенный режим — возвращаем только содержимое
    if (widget.embedded) {
      return body;
    }

    // Полноэкранный режим (мобильные устройства или отдельная страница)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Запросы в друзья'),
        actions: [
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Обновить',
            onPressed: () {
              final prov =
                  Provider.of<FriendsProvider>(context, listen: false);
              prov.fetchIncomingRequests(refresh: true);
            },
          ),
        ],
      ),
      body: body,
    );
  }
}

class _EmptyRequestsView extends StatelessWidget {
  final ThemeData theme;
  const _EmptyRequestsView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_disabled,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 24),
            Text('Запросов нет',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Когда кто-то захочет добавить вас в друзья, запрос появится здесь.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> requests;
  final bool hasMore;
  final bool isLoadingMore;
  final Set<String> loadingIds;
  final VoidCallback onLoadMore;
  final Function(String) onAccept;
  final Function(String) onDecline;

  const _RequestsList({
    required this.theme,
    required this.requests,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadingIds,
    required this.onLoadMore,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length + (hasMore || isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= requests.length) {
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Загрузить ещё'),
            ),
          );
        }

        final r = requests[i];
        final requestId = r['id'] as String;
        final sender = r['sender'] as Map<String, dynamic>?;
        final isLoading = loadingIds.contains(requestId);

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          color: theme.cardColor,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                  backgroundImage: sender?['avatarUrl'] != null &&
                          sender!['avatarUrl']!.isNotEmpty
                      ? NetworkImage(sender!['avatarUrl'])
                      : null,
                  child: sender?['avatarUrl'] == null ||
                          sender!['avatarUrl']!.isEmpty
                      ? Icon(Icons.person, color: theme.colorScheme.primary)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender?['displayName'] ?? 'Неизвестный',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Хочет добавить вас в друзья',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.colorScheme.primary),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        icon: Icons.check_circle,
                        color: theme.colorScheme.primary,
                        tooltip: 'Принять',
                        onPressed: () => onAccept(requestId),
                      ),
                      const SizedBox(width: 4),
                      AppIconButton(
                        icon: Icons.close,
                        color: theme.colorScheme.error,
                        tooltip: 'Отклонить',
                        onPressed: () => onDecline(requestId),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}