import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/screen_chrome.dart';

class SessionResultsScreen extends StatelessWidget {
  const SessionResultsScreen({
    super.key,
    this.mutualLikes,
    this.embedded = false,
    this.onClose,
  });

  final List<Map>? mutualLikes;

  final bool embedded;

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final tracks = mutualLikes ??
        (args?['mutualLikes'] as List?)?.whereType<Map>().toList() ??
        const <Map>[];
    final hasResults = tracks.isNotEmpty;

    final body = Column(
      children: [
        Expanded(
          child: hasResults ? _ResultsList(tracks: tracks) : const _NoMatchesView(),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton(
            onPressed: () {
              if (embedded) {
                onClose?.call();
                return;
              }
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
            },
            child: Text(embedded ? L.of(context).cropDone : L.of(context).resultsBackHome),
          ),
        ),
      ],
    );

    if (embedded) return SafeArea(child: body);

    return ScreenChrome(
      header: ScreenHeader(
        title: L.of(context).resultsTitle,
        onBack: () => Navigator.of(context).pop(),
      ),
      child: body,
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.tracks});

  final List<Map> tracks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      itemCount: tracks.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.of(context).resultsMatches, style: texts.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  L.of(context).resultsMatchesHint,
                  style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final track = tracks[i - 1];
        return _MatchTile(
          index: i,
          trackName: track['trackName'] as String? ?? L.of(context).historyUntitled,
          artistName: track['artistName'] as String? ?? '',
          imageUrl: track['imageUrl'] as String?,
        );
      },
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.index,
    required this.trackName,
    required this.artistName,
    required this.imageUrl,
  });

  final int index;
  final String trackName;
  final String artistName;
  final String? imageUrl;

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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.small,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.favorite_rounded, color: colors.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trackName,
                  style: texts.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artistName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    artistName,
                    style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMatchesView extends StatelessWidget {
  const _NoMatchesView();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.music_off_rounded,
      title: L.of(context).resultsNoMatches,
      message: L.of(context).resultsNoMatchesHint,
    );
  }
}