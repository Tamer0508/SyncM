import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

/// История прослушанного.
class PlayHistoryScreen extends StatefulWidget {
  const PlayHistoryScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<PlayHistoryScreen> createState() => _PlayHistoryScreenState();
}

class _PlayHistoryScreenState extends State<PlayHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<AuthProvider>().api;
      final list = await api.getPlayHistory();
      if (!mounted) return;
      setState(() => _items = list);
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Очистить историю?',
      message: 'Записи о прослушанных треках будут удалены.',
      confirmLabel: 'Очистить',
    );

    if (!confirmed || !mounted) return;

    try {
      final ok = await context.read<AuthProvider>().api.clearPlayHistory();
      if (!mounted) return;
      if (ok) {
        setState(() => _items = []);
        showSuccess(context, 'История очищена');
      } else {
        showError(context, 'Не удалось очистить историю', force: true);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  /// Когда трек играл — словами.
  ///
  /// Точное время здесь не нужно: важно «сегодня» или «на прошлой неделе»,
  /// а не «14:32». Дату показываем, только когда прошло больше недели.
  String _formatWhen(String? raw) {
    if (raw == null) return '';
    final at = DateTime.tryParse(raw)?.toLocal();
    if (at == null) return '';

    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return '${diff.inHours} ч. назад';
    if (diff.inDays == 1) return 'вчера';
    if (diff.inDays < 7) return '${diff.inDays} д. назад';
    return '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: 'История',
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: [
          if (_items.isNotEmpty)
            AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Очистить',
              onPressed: _clear,
            ),
        ],
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(child: SkeletonTrackList(itemCount: 6));
    }

    if (_items.isEmpty) return const _EmptyHistory();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xl,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, i) {
          final item = _items[i];
          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHigh,
                borderRadius: AppRadius.small,
              ),
              child: Icon(Icons.music_note_rounded,
                  size: 20, color: context.colors.onSurfaceVariant),
            ),
            title: Text(
              item['trackName'] as String? ?? 'Без названия',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item['artistName'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _formatWhen(item['playedAt'] as String?),
              style: context.texts.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.history_rounded,
      title: 'История пуста',
      message: 'Здесь появятся треки, которые вы включали в SyncM.',
    );
  }
}