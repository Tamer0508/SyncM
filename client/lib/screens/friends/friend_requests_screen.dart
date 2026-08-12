import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/friends_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/tappable_avatar.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<FriendsProvider>();
      prov.markAsRead();
      prov.fetchIncomingRequests(refresh: true);
    });
  }

  Future<void> _acceptRequest(String requestId) async {
    if (_loadingIds.contains(requestId)) return;
    setState(() => _loadingIds.add(requestId));
    try {
      await context.read<FriendsProvider>().acceptRequest(requestId);
      if (!mounted) return;
      showSuccess(context, 'Заявка принята');
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(requestId));
    }
  }

  Future<void> _declineRequest(String requestId, String senderName) async {
    if (_loadingIds.contains(requestId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.person_remove_rounded, color: ctx.colors.error),
        title: const Text('Отклонить заявку?'),
        content: Text('$senderName не увидит, что вы отклонили заявку.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.error,
              foregroundColor: ctx.colors.onError,
            ),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loadingIds.add(requestId));
    try {
      await context.read<FriendsProvider>().deleteRequest(requestId);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enablePullToRefresh = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    final body = Consumer<FriendsProvider>(
      builder: (context, prov, _) {
        final isInitialLoad = prov.incomingLoading && prov.incomingRequests.isEmpty;

        if (isInitialLoad) {
          return const SingleChildScrollView(child: SkeletonList(itemCount: 4));
        }

        if (prov.incomingRequests.isEmpty) {
          // ListView, а не Center: пустое состояние тоже должно тянуться вниз,
          // иначе жест обновления на нём не срабатывает. Раньше для этого
          // задавалась высота через MediaQuery минус kToolbarHeight — расчёт
          // ломался во встроенном режиме, где панели сверху нет вовсе.
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 80),
              _EmptyRequestsView(),
            ],
          );
        }

        return _RequestsList(
          requests: prov.incomingRequests,
          hasMore: prov.hasMoreIncoming,
          isLoadingMore: prov.incomingLoading,
          loadingIds: _loadingIds,
          onLoadMore: prov.fetchIncomingRequests,
          onAccept: _acceptRequest,
          onDecline: _declineRequest,
        );
      },
    );

    final content = enablePullToRefresh
        ? RefreshIndicator(
            onRefresh: () =>
                context.read<FriendsProvider>().fetchIncomingRequests(refresh: true),
            child: body,
          )
        : body;

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: 'Заявки в друзья',
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Обновить',
            onPressed: () =>
                context.read<FriendsProvider>().fetchIncomingRequests(refresh: true),
          ),
        ],
      ),
      child: content,
    );
  }
}

class _EmptyRequestsView extends StatelessWidget {
  const _EmptyRequestsView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_email_read_rounded,
            size: 72,
            color: colors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Заявок нет', style: texts.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Когда кто-то захочет добавить вас в друзья, заявка появится здесь.',
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.requests,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadingIds,
    required this.onLoadMore,
    required this.onAccept,
    required this.onDecline,
  });

  final List<Map<String, dynamic>> requests;
  final bool hasMore;
  final bool isLoadingMore;
  final Set<String> loadingIds;
  final VoidCallback onLoadMore;
  final void Function(String requestId) onAccept;
  final void Function(String requestId, String senderName) onDecline;

  @override
  Widget build(BuildContext context) {
    final showFooter = hasMore || isLoadingMore;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: requests.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm + 4),
      itemBuilder: (context, i) {
        if (i >= requests.length) {
          if (isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return OutlinedButton(
            onPressed: onLoadMore,
            child: const Text('Загрузить ещё'),
          );
        }

        final request = requests[i];
        final requestId = request['id'] as String;
        final sender = request['sender'] as Map<String, dynamic>?;
        final senderName = sender?['displayName'] as String? ?? 'Пользователь';
        final avatarUrl = sender?['avatarUrl'] as String?;

        return _RequestCard(
          requestId: requestId,
          senderName: senderName,
          avatarUrl: avatarUrl,
          isLoading: loadingIds.contains(requestId),
          onAccept: () => onAccept(requestId),
          onDecline: () => onDecline(requestId, senderName),
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.requestId,
    required this.senderName,
    required this.avatarUrl,
    required this.isLoading,
    required this.onAccept,
    required this.onDecline,
  });

  final String requestId;
  final String senderName;
  final String? avatarUrl;
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          TappableAvatar(
            imageUrl: avatarUrl,
            radius: 26,
            title: senderName,
            heroTag: 'request-$requestId',
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: texts.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Хочет добавить вас в друзья',
                  style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Отклонение — второстепенное действие, поэтому контурная
                // иконка, а принятие выделено заливкой. Раньше обе кнопки
                // выглядели одинаково, и различить их можно было только по
                // цвету, что плохо работает при дальтонизме.
                IconButton(
                  onPressed: onDecline,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Отклонить',
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Принять',
                ),
              ],
            ),
        ],
      ),
    );
  }
}