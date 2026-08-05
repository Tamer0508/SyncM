import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../theme.dart';

enum NotificationType { success, error, info }

void showAppNotification(
  BuildContext context, {
  required String message,
  NotificationType type = NotificationType.info,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _NotificationHost.show(
    context,
    _NotificationData(
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

class _NotificationData {
  _NotificationData({
    required this.message,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final NotificationType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  final key = UniqueKey();
}

class _NotificationHost {
  _NotificationHost._();

  static const _maxVisible = 3;

  static final Queue<_NotificationData> _pending = Queue();
  static final List<_NotificationData> _visible = [];
  static OverlayEntry? _entry;
  static final Map<Key, Timer> _timers = {};

  static void show(BuildContext context, _NotificationData data) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      debugPrint('showAppNotification: Overlay недоступен, пропущено: ${data.message}');
      return;
    }

    if (_visible.length >= _maxVisible) {
      _pending.add(data);
      return;
    }

    _visible.insert(0, data);
    _timers[data.key] = Timer(data.duration, () => dismiss(data.key));

    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => const _NotificationStack());
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  static void dismiss(Key key) {
    _timers.remove(key)?.cancel();
    final removed = _visible.any((d) => d.key == key);
    if (!removed) return;

    _visible.removeWhere((d) => d.key == key);

    // Освободилось место — показываем следующее из очереди.
    if (_pending.isNotEmpty && _visible.length < _maxVisible) {
      final next = _pending.removeFirst();
      _visible.insert(0, next);
      _timers[next.key] = Timer(next.duration, () => dismiss(next.key));
    }

    if (_visible.isEmpty) {
      _entry?.remove();
      _entry?.dispose();
      _entry = null;
    } else {
      _entry?.markNeedsBuild();
    }
  }

  static List<_NotificationData> get visible => List.unmodifiable(_visible);
}

class _NotificationStack extends StatefulWidget {
  const _NotificationStack();

  @override
  State<_NotificationStack> createState() => _NotificationStackState();
}

class _NotificationStackState extends State<_NotificationStack> {
  bool _expanded = false;

  /// На сколько точек выглядывает каждая следующая карточка в стопке.
  static const _peek = 12.0;

  /// Расстояние между карточками в разъехавшемся виде.
  static const _gap = 8.0;

  /// Насколько уменьшается каждая карточка вглубь стопки.
  static const _scaleStep = 0.05;

  @override
  Widget build(BuildContext context) {
    final items = _NotificationHost.visible;
    if (items.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final isCompact = size.width < 600;

    final growsUp = isCompact;
    final maxWidth = isCompact ? size.width - AppSpacing.md * 2 : 400.0;

    const cardHeight = 68.0;
    final extra = _expanded
        ? (items.length - 1) * (cardHeight + _gap)
        : (items.length - 1) * _peek;

    return Positioned(
      top: growsUp ? null : padding.top + AppSpacing.md,
      bottom: growsUp ? padding.bottom + AppSpacing.md : null,
      left: isCompact ? AppSpacing.md : null,
      right: AppSpacing.md,
      child: MouseRegion(
        onEnter: (_) => setState(() => _expanded = true),
        onExit: (_) => setState(() => _expanded = false),
        child: GestureDetector(
          // На телефоне мыши нет — разворачиваем нажатием по стопке.
          onTap: items.length > 1 ? () => setState(() => _expanded = !_expanded) : null,
          child: SizedBox(
            width: maxWidth,
            height: cardHeight + extra,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = items.length - 1; i >= 0; i--)
                  _StackedItem(
                    key: items[i].key,
                    data: items[i],
                    depth: i,
                    expanded: _expanded,
                    growsUp: growsUp,
                    peek: _peek,
                    gap: _gap,
                    cardHeight: cardHeight,
                    scaleStep: _scaleStep,
                    onDismiss: () => _NotificationHost.dismiss(items[i].key),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StackedItem extends StatelessWidget {
  const _StackedItem({
    super.key,
    required this.data,
    required this.depth,
    required this.expanded,
    required this.growsUp,
    required this.peek,
    required this.gap,
    required this.cardHeight,
    required this.scaleStep,
    required this.onDismiss,
  });

  final _NotificationData data;
  final int depth;
  final bool expanded;
  final bool growsUp;
  final double peek;
  final double gap;
  final double cardHeight;
  final double scaleStep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final offset = expanded ? depth * (cardHeight + gap) : depth * peek;

    final scale = expanded ? 1.0 : 1 - depth * scaleStep;

    return AnimatedPositioned(
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
      top: growsUp ? null : offset,
      bottom: growsUp ? offset : null,
      left: 0,
      right: 0,
      child: AnimatedScale(
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
        scale: scale,
        alignment: growsUp ? Alignment.bottomCenter : Alignment.topCenter,
        child: AnimatedOpacity(
          duration: AppMotion.medium,
          opacity: expanded ? 1.0 : (1 - depth * 0.25).clamp(0.35, 1.0),
          child: _NotificationCard(
            data: data,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    super.key,
    required this.data,
    required this.onDismiss,
  });

  final _NotificationData data;
  final VoidCallback onDismiss;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.medium)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({Color accent, IconData icon}) _style(BuildContext context) {
    final colors = context.colors;
    return switch (widget.data.type) {
      NotificationType.success => (accent: context.brand.online, icon: Icons.check_circle_rounded),
      NotificationType.error => (accent: colors.error, icon: Icons.error_rounded),
      NotificationType.info => (accent: colors.primary, icon: Icons.info_rounded),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final style = _style(context);
    final data = widget.data;

    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.emphasizedDecelerate,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(curved),
        child: Dismissible(
                key: ValueKey('dismiss_${data.key}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => widget.onDismiss(),
                child: Material(
                  color: colors.surfaceContainerHigh,
                  borderRadius: AppRadius.large,
                  clipBehavior: Clip.antiAlias,
                  elevation: 3,
                  shadowColor: colors.shadow.withValues(alpha: 0.3),
                  child: InkWell(
                    onTap: widget.onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm + 4,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: style.accent.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(style.icon, color: style.accent, size: 19),
                          ),
                          const SizedBox(width: AppSpacing.sm + 4),
                          Expanded(
                            child: Text(
                              data.message,
                              style: texts.bodyMedium?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (data.actionLabel != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            TextButton(
                              onPressed: () {
                                widget.onDismiss();
                                data.onAction?.call();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: style.accent,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(data.actionLabel!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}