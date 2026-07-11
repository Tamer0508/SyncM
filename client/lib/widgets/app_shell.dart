import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/playback_provider.dart';
import 'mini_player.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final hasActiveTrack = playback.currentTrack != null;
    final isMobile = MediaQuery.of(context).size.width < 900;

    final bottomInset = hasActiveTrack && isMobile ? 92.0 : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: child,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: hasActiveTrack
                  ? SafeArea(
                      key: const ValueKey('mini_player'),
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, isMobile ? 8 : 12),
                        child: const MiniPlayer(),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('mini_player_empty')),
            ),
          ),
        ],
      ),
    );
  }
}
