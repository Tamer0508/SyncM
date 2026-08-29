import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;

  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<AuthProvider>().api;
      final list = await api.getBlockedUsers();
      if (!mounted) return;
      setState(() => _blocked = list);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(Map<String, dynamic> user) async {
    final id = user['id'] as String?;
    if (id == null || _pending.contains(id)) return;

    setState(() => _pending.add(id));
    try {
      final api = context.read<AuthProvider>().api;
      final ok = await api.unblockUser(id);
      if (!mounted) return;

      if (ok) {
        setState(() => _blocked.removeWhere((u) => u['id'] == id));
        context.read<FriendsProvider>().fetchFriends(refresh: true).ignore();
        showSuccess(
          context,
          L.of(context).blockedUnblocked(
            user['displayName'] as String? ?? L.of(context).commonUser,
          ),
        );
      } else {
        showError(context, L.of(context).blockedUnblockFailed, force: true);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: L.of(context).privacyBlocked,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(child: SkeletonBlockedList(itemCount: 4));
    }

    if (_blocked.isEmpty) return const _EmptyBlocked();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: _blocked.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              L.of(context).blockedHint,
              style: context.texts.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          );
        }

        final user = _blocked[i - 1];
        final id = user['id'] as String? ?? '';

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: AppRadius.large,
          ),
          child: Row(
            children: [
              TappableAvatar(
                imageUrl: user['avatarUrl'] as String?,
                radius: 22,
                title: user['displayName'] as String?,
                heroTag: 'blocked-$id',
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  user['displayName'] as String? ?? L.of(context).commonUser,
                  style: context.texts.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_pending.contains(id))
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: () => _unblock(user),
                  child: Text(L.of(context).blockedUnblock),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyBlocked extends StatelessWidget {
  const _EmptyBlocked();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.block_rounded,
      title: L.of(context).blockedEmptyTitle,
      message: L.of(context).blockedEmptyMessage,
    );
  }
}