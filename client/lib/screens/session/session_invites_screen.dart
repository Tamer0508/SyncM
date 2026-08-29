import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/skeleton.dart';

class SessionInvitesScreen extends StatefulWidget {
  const SessionInvitesScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;

  final VoidCallback? onBack;

  @override
  State<SessionInvitesScreen> createState() => _SessionInvitesScreenState();
}

class _SessionInvitesScreenState extends State<SessionInvitesScreen> {
  final Set<String> _responding = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<SessionProvider>();
      prov.markInvitesAsRead();
      prov.fetchInvites();
    });
  }

  Future<void> _respond(String sessionId, bool accept) async {
    if (_responding.contains(sessionId)) return;
    setState(() => _responding.add(sessionId));

    try {
      final result = await context.read<SessionProvider>().respondToInvite(sessionId, accept);
      if (!mounted) return;

      if (result == null) {
        showError(context, L.of(context).invitesReplyFailed, force: true);
        return;
      }

      if (!accept) {
        showSuccess(context, L.of(context).invitesDeclined);
        return;
      }

      final session = result['session'] as Map<String, dynamic>?;
      if (session != null) {
        if (context.isWideWindow) {
          context.read<SessionProvider>().requestOpenSession(session);
          unawaited(Navigator.of(context).maybePop());
          return;
        }
        unawaited(Navigator.of(context)
            .pushReplacementNamed('/session', arguments: session));
      } else {
        showSuccess(context, L.of(context).invitesAccepted);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _responding.remove(sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {

    final body = Consumer<SessionProvider>(
      builder: (context, prov, _) {
        if (prov.invitesLoading && prov.invites.isEmpty) {
          return const SingleChildScrollView(child: SkeletonInviteList(itemCount: 3));
        }

        if (prov.invites.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 80), _EmptyInvitesView()],
          );
        }

        return _InvitesList(
          invites: prov.invites,
          hostNameForInvite: prov.hostNameForInvite,
          responding: _responding,
          onAccept: (id) => _respond(id, true),
          onDecline: (id) => _respond(id, false),
        );
      },
    );

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: L.of(context).invitesTitle,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: L.of(context).commonRefresh,
            onPressed: () =>
                context.read<SessionProvider>().fetchInvites(),
          ),
        ],
      ),
      child: body,
    );
  }
}

class _EmptyInvitesView extends StatelessWidget {
  const _EmptyInvitesView();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.mail_outline_rounded,
      title: L.of(context).invitesEmptyTitle,
      message: L.of(context).invitesEmptyMessage,
      actionLabel: L.of(context).homeStartSession,
      onAction: () => Navigator.of(context).pushNamed('/session/create'),
    );
  }
}

class _InvitesList extends StatelessWidget {
  const _InvitesList({
    required this.invites,
    required this.hostNameForInvite,
    required this.responding,
    required this.onAccept,
    required this.onDecline,
  });

  final List<Map<String, dynamic>> invites;
  final String? Function(Map<String, dynamic>) hostNameForInvite;
  final Set<String> responding;
  final void Function(String sessionId) onAccept;
  final void Function(String sessionId) onDecline;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: invites.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm + 4),
      itemBuilder: (context, i) {
        final invite = invites[i];
        final sessionId = invite['id'] as String;

        return _InviteCard(
          sessionName: invite['name'] as String? ?? L.of(context).homeSession,
          hostName: hostNameForInvite(invite) ?? L.of(context).homeFilterFriend,
          trackCount: (invite['tracks'] as List?)?.length ?? 0,
          isResponding: responding.contains(sessionId),
          onAccept: () => onAccept(sessionId),
          onDecline: () => onDecline(sessionId),
        );
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.sessionName,
    required this.hostName,
    required this.trackCount,
    required this.isResponding,
    required this.onAccept,
    required this.onDecline,
  });

  final String sessionName;
  final String hostName;
  final int trackCount;
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: AppRadius.small,
                ),
                child: Icon(Icons.headphones_rounded, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionName,
                      style: texts.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L.of(context).homeInviteFrom(hostName),
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (trackCount > 0) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            Row(
              children: [
                Icon(Icons.queue_music_rounded, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  L.of(context).trackCount(trackCount),
                  style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isResponding ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                  ),
                  child: Text(L.of(context).requestsDecline),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: FilledButton(
                  onPressed: isResponding ? null : onAccept,
                  child: isResponding
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        )
                      : Text(L.of(context).requestsAccept),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}