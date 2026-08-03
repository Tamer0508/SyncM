import 'package:flutter/material.dart';

enum NotificationType { success, error, info }

OverlayEntry? _currentEntry;

void showAppNotification(
  BuildContext context, {
  required String message,
  NotificationType type = NotificationType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  _currentEntry?.remove();
  _currentEntry?.dispose();

  final theme = Theme.of(context);
  final overlay = Overlay.of(context);
  final topPadding = MediaQuery.of(context).padding.top + 16;

  Color backgroundColor;
  IconData icon;
  switch (type) {
    case NotificationType.success:
      backgroundColor = Colors.green.shade600;
      icon = Icons.check_circle_outline;
      break;
    case NotificationType.error:
      backgroundColor = theme.colorScheme.error;
      icon = Icons.error_outline;
      break;
    case NotificationType.info:
    default:
      backgroundColor = theme.colorScheme.primary;
      icon = Icons.info_outline;
  }

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AnimatedNotification(
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      topPadding: topPadding,
      onDismiss: () {
        entry.remove();
        entry.dispose();
        if (_currentEntry == entry) _currentEntry = null;
      },
      duration: duration,
    ),
  );

  _currentEntry = entry;
  overlay.insert(entry);
}

class _AnimatedNotification extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final double topPadding;
  final VoidCallback onDismiss;
  final Duration duration;

  const _AnimatedNotification({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.topPadding,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_AnimatedNotification> createState() => _AnimatedNotificationState();
}

class _AnimatedNotificationState extends State<_AnimatedNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    _controller.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Dismissible(
            key: const ValueKey('notification'),
            direction: DismissDirection.up,
            onDismissed: (_) => _dismiss(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.backgroundColor.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(Icons.close, color: Colors.white70, size: 20),
                    ),
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