import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'mini_player.dart';

@immutable
class ScreenHeader {
  const ScreenHeader({
    required this.title,
    this.actions = const [],
    this.onBack,
  });

  final String title;

  final List<Widget> actions;

  final VoidCallback? onBack;
}

class ScreenChrome extends StatelessWidget {
  const ScreenChrome({
    super.key,
    required this.header,
    required this.child,
    this.embedded = false,
  });

  final ScreenHeader header;
  final Widget child;

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final bar = _HeaderBar(header: header);

    if (embedded) {
      return Column(
        children: [
          bar,
          Expanded(child: child),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            bar,
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayerDock(),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.header});

  final ScreenHeader header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (header.onBack != null)
            IconButton(
              onPressed: header.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: L.of(context).commonBack,
            )
          else
            const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              header.title,
              style: context.texts.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...header.actions,
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}