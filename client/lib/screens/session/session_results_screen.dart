import 'package:flutter/material.dart';

import '../../theme.dart';

class SessionResultsScreen extends StatelessWidget {
  const SessionResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final mutualLikes =
        (args?['mutualLikes'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final hasResults = mutualLikes.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Итоги сессии')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: hasResults
                  ? _ResultsList(tracks: mutualLikes)
                  : const _NoMatchesView(),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  '/home',
                  (_) => false,
                ),
                child: const Text('На главную'),
              ),
            ),
          ],
        ),
      ),
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
                Text('Совпадения', style: texts.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Эти треки понравились обоим.',
                  style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final track = tracks[i - 1];
        return _MatchTile(
          index: i,
          trackName: track['trackName'] as String? ?? 'Без названия',
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
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
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
    final colors = context.colors;
    final texts = context.texts;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 72,
              color: colors.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Совпадений нет', style: texts.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'В этот раз вкусы разошлись. Попробуйте ещё одну сессию - '
              'с другой подборкой результат может быть иным.',
              textAlign: TextAlign.center,
              style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}