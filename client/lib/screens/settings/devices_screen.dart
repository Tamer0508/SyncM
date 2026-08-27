import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/playlists_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/skeleton.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;

  /// Какие сеансы сейчас завершаются — чтобы не нажать дважды.
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() => _loading = true);
    try {
      final api = context.read<AuthProvider>().api;
      final list = await api.getAuthDevices(refresh: refresh);
      if (!mounted) return;
      setState(() => _devices = list);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    final id = device['id'] as String?;
    if (id == null || _pending.contains(id)) return;

    final isCurrent = device['current'] == true;
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: isCurrent
          ? L.of(context).devicesSignOutThisDeviceTitle
          : L.of(context).devicesEndSessionTitle,
      message: isCurrent
          ? L.of(context).securitySignOutMessage
          : L.of(context).devicesEndAgainMessage(_name(device)),
      confirmLabel: L.of(context).commonFinish,
    );
    if (!confirmed || !mounted) return;

    setState(() => _pending.add(id));
    try {
      final wasCurrent = await context.read<AuthProvider>().api.revokeDevice(id);
      if (!mounted) return;

      if (wasCurrent) {
        await _leaveApp();
        return;
      }

      setState(() => _devices.removeWhere((d) => d['id'] == id));
      showSuccess(context, L.of(context).devicesSessionEnded);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _logoutEverywhere() async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.phonelink_erase_rounded,
      title: L.of(context).securitySignOutEverywhereTitle,
      message: L.of(context).securitySignOutEverywhereMessage,
      confirmLabel: L.of(context).securitySignOutEverywhereConfirm,
    );
    if (!confirmed || !mounted) return;

    try {
      await context.read<AuthProvider>().logoutEverywhere();
      if (!mounted) return;
      await _leaveApp(alreadyLoggedOut: true);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  /// Общий хвост выхода: остановить плеер, забыть данные, уйти на вход.
  Future<void> _leaveApp({bool alreadyLoggedOut = false}) async {
    // Проигрыватель переживает смену аккаунта: без остановки следующий
    // вошедший увидел бы панель с чужим треком.
    await context.read<PlaybackProvider>().stopAndClear();
    if (!mounted) return;

    context.read<PlaylistsProvider>().reset();

    if (!alreadyLoggedOut) {
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
    }

    unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false));
  }

  String _name(Map<String, dynamic> device) {
    final info = device['device'];
    final name = info is Map ? info['name'] as String? : null;
    if (name != null && name.isNotEmpty) return name;

    return device['kind'] == 'web'
        ? L.of(context).devicesBrowser
        : L.of(context).devicesApp;
  }

  static IconData _icon(Map<String, dynamic> device) {
    final info = device['device'];
    final platform = info is Map ? info['platform'] as String? : null;

    return switch (platform) {
      'Android' || 'iOS' => Icons.smartphone_rounded,
      'Windows' || 'macOS' || 'Linux' || 'ChromeOS' => Icons.laptop_rounded,
      _ => device['kind'] == 'web'
          ? Icons.public_rounded
          : Icons.devices_other_rounded,
    };
  }

  String _lastSeen(Map<String, dynamic> device) {
    final l = L.of(context);
    final ms = device['lastSeenAt'];
    if (ms is! int) return l.devicesTimeUnknown;

    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));

    if (diff.inMinutes < 5) return l.tabNow;
    if (diff.inMinutes < 60) return l.minutesAgoShort(diff.inMinutes);
    if (diff.inHours < 24) return l.hoursAgoShort(diff.inHours);
    if (diff.inDays == 1) return l.devicesYesterday;
    return l.daysAgoShort(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: L.of(context).devicesTitle,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(child: SkeletonDeviceList(itemCount: 3));
    }

    if (_devices.isEmpty) {
      return EmptyState(
        icon: Icons.devices_rounded,
        title: L.of(context).devicesEmptyTitle,
        message: L.of(context).devicesEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _devices.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                L.of(context).devicesHint,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            );
          }

          if (i == _devices.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: OutlinedButton.icon(
                onPressed: _logoutEverywhere,
                icon: const Icon(Icons.phonelink_erase_rounded),
                label: Text(L.of(context).securitySignOutEverywhere),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.error,
                  side: BorderSide(
                      color: context.colors.error.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            );
          }

          final device = _devices[i - 1];

          return _DeviceTile(
            device: device,
            busy: _pending.contains(device['id']),
            name: _name(device),
            icon: _icon(device),
            lastSeen: _lastSeen(device),
            onRevoke: () => _revoke(device),
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.busy,
    required this.name,
    required this.icon,
    required this.lastSeen,
    required this.onRevoke,
  });

  final Map<String, dynamic> device;
  final bool busy;
  final String name;
  final IconData icon;
  final String lastSeen;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final isCurrent = device['current'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          Icon(icon, color: isCurrent ? colors.primary : colors.onSurface),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: texts.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const _CurrentBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  lastSeen,
                  style:
                      texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: onRevoke,
              child: Text(isCurrent ? L.of(context).commonSignOut : L.of(context).commonFinish),
            ),
        ],
      ),
    );
  }
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.16),
        borderRadius: AppRadius.small,
      ),
      child: Text(
        L.of(context).devicesCurrent,
        style: context.texts.labelSmall?.copyWith(color: colors.primary),
      ),
    );
  }
}
