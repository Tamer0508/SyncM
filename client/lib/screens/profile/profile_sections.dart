import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/playlists_provider.dart';
import '../../theme.dart';
import '../../utils/image_cache.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/skeleton.dart';
import 'music_summary.dart';

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({
    super.key,
    required this.title,
    this.hint,
    this.trailing = const [],
  });

  final String title;
  final String? hint;

  /// Кнопки и стрелка справа от заголовка.
  final List<Widget> trailing;

  /// Отступ сверху, отделяющий раздел от предыдущего.
  static const EdgeInsets outerPadding = EdgeInsets.only(top: AppSpacing.lg);

  /// Боковые отступы содержимого разделов.
  static const EdgeInsets sidePadding =
      EdgeInsets.symmetric(horizontal: AppSpacing.md);

  /// Промежуток между шапкой и содержимым раздела.
  static const double gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final subtitle = hint;

    return Padding(
      padding: sidePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: texts.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: texts.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class ProfileArtistsSection extends StatelessWidget {
  const ProfileArtistsSection({
    super.key,
    required this.artists,
    this.maxCount = 10,
  });

  final List<ArtistTally> artists;

  final int maxCount;

  /// Размеры кружка и колонки под ним.
  static const double avatarNarrow = 72;
  static const double avatarWide = 88;
  static const double _wideFrom = 700;

  static double avatarSizeFor(double width) =>
      width >= _wideFrom ? avatarWide : avatarNarrow;

  static TextStyle? nameStyle(BuildContext context) =>
      context.texts.titleSmall?.copyWith(height: 1.35);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Padding(
      padding: ProfileSectionHeader.outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileSectionHeader(
            title: l.profileTopArtists,
            hint: l.profileTopArtistsHint,
          ),
          const SizedBox(height: ProfileSectionHeader.gap),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = avatarSizeFor(constraints.maxWidth);
              final visible =
                  artists.length > maxCount ? maxCount : artists.length;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: ProfileSectionHeader.sidePadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < visible; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      _ArtistTile(artist: artists[i], size: size),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist, required this.size});

  final ArtistTally artist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final image = artist.imageUrl;

    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: image == null
                  ? _ArtistFallback(colors: colors)
                  : AppNetworkImage(
                      url: image,
                      width: size,
                      height: size,
                      placeholder: _ArtistFallback(colors: colors),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ProfileArtistsSection.nameStyle(context),
          ),
          const SizedBox(height: 2),
          Text(
            L.of(context).trackCount(artist.trackCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ArtistFallback extends StatelessWidget {
  const _ArtistFallback({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.surfaceContainerHigh,
      child: Icon(
        Icons.person_rounded,
        color: colors.onSurfaceVariant,
        size: 28,
      ),
    );
  }
}

class ProfileSharedMusicSection extends StatelessWidget {
  const ProfileSharedMusicSection({
    super.key,
    required this.shared,
    this.maxArtists = 8,
  });

  final SharedMusic shared;
  final int maxArtists;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final l = L.of(context);

    final artists = shared.artists.length > maxArtists
        ? shared.artists.sublist(0, maxArtists)
        : shared.artists;

    return Padding(
      padding: ProfileSectionHeader.outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileSectionHeader(
            title: l.profileInCommonTitle,
            hint: l.profileInCommonHint,
          ),
          const SizedBox(height: ProfileSectionHeader.gap),
          Padding(
            padding: ProfileSectionHeader.sidePadding,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: AppRadius.large,
              ),
              child: shared.isEmpty
                  ? Text(
                      l.profileInCommonEmpty,
                      style: texts.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (artists.isNotEmpty)
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final name in artists) _ArtistChip(name: name),
                            ],
                          ),
                        if (shared.tracks.isNotEmpty) ...[
                          if (artists.isNotEmpty)
                            const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Icon(
                                Icons.music_note_rounded,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  l.profileInCommonTracks(
                                    shared.tracks.length,
                                  ),
                                  style: texts.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistChip extends StatelessWidget {
  const _ArtistChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        name,
        style: context.texts.labelLarge
            ?.copyWith(color: colors.onPrimaryContainer),
      ),
    );
  }
}


/// Свои подборки — карусель из тех же карточек, что и на вкладке «Музыка».
class ProfilePlaylistsSection extends StatelessWidget {
  const ProfilePlaylistsSection({
    super.key,
    required this.playlists,
    required this.onOpen,
    this.maxCount = 10,
  });

  final List<Map<String, dynamic>> playlists;
  final void Function(Map<String, dynamic> playlist) onOpen;
  final int maxCount;

  /// Ширина карточки и высота полосы: обложка плюс две строки подписи.
  static const double cardWidth = 150;

  static double stripHeightFor(BuildContext context) {
    final texts = context.texts;

    final labels = textLineHeight(context, texts.titleSmall) +
        2 +
        textLineHeight(context, texts.bodySmall);

    // Обложка квадратная, под ней отступы карточки: 8 сверху и 12 снизу.
    return cardWidth + AppSpacing.sm + AppSpacing.sm + 4 + labels;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final visible =
        playlists.length > maxCount ? playlists.sublist(0, maxCount) : playlists;

    return Padding(
      padding: ProfileSectionHeader.outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileSectionHeader(
            title: l.profilePlaylistsTitle,
            hint: l.profilePlaylistsHint,
          ),
          const SizedBox(height: ProfileSectionHeader.gap),
          SizedBox(
            height: stripHeightFor(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: ProfileSectionHeader.sidePadding,
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, i) {
                final playlist = visible[i];
                return PlaylistCard(
                  width: cardWidth,
                  name: playlist.playlistName,
                  description: L
                      .of(context)
                      .trackCount(playlist.playlistTrackCount),
                  imageUrl: playlist.playlistImageUrl,
                  onTap: () => onOpen(playlist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


/// Шапка раздела-заглушки.
class _SkeletonSectionHeader extends StatelessWidget {
  const _SkeletonSectionHeader({required this.titleFactor, this.hintFactor});

  final double titleFactor;
  final double? hintFactor;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final hint = hintFactor;

    return Padding(
      padding: ProfileSectionHeader.sidePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonLine(style: texts.titleLarge, widthFactor: titleFactor),
          if (hint != null) ...[
            const SizedBox(height: 2),
            SkeletonLine(style: texts.bodySmall, widthFactor: hint),
          ],
        ],
      ),
    );
  }
}

/// Зеркало [ProfileArtistsSection].
class SkeletonProfileArtists extends StatelessWidget {
  const SkeletonProfileArtists({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Skeleton(
      child: Padding(
        padding: ProfileSectionHeader.outerPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkeletonSectionHeader(titleFactor: 0.5, hintFactor: 0.42),
            const SizedBox(height: ProfileSectionHeader.gap),
            LayoutBuilder(
              builder: (context, constraints) {
                final size =
                    ProfileArtistsSection.avatarSizeFor(constraints.maxWidth);

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: ProfileSectionHeader.sidePadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < itemCount; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        SizedBox(
                          width: size,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SkeletonBox(
                                width: size,
                                height: size,
                                circle: true,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SkeletonLine(
                                style: ProfileArtistsSection.nameStyle(context),
                                widthFactor: 0.85,
                              ),
                              const SizedBox(height: 2),
                              SkeletonLine(
                                style: texts.bodySmall,
                                widthFactor: 0.6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Зеркало [ProfileSharedMusicSection].
class SkeletonProfileSharedMusic extends StatelessWidget {
  const SkeletonProfileSharedMusic({super.key, this.chipCount = 4});

  final int chipCount;

  /// Доли ширины под названия исполнителей в фишках.
  static const List<double> _chipFactors = [0.26, 0.18, 0.32, 0.22];

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Skeleton(
      child: Padding(
        padding: ProfileSectionHeader.outerPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkeletonSectionHeader(titleFactor: 0.44, hintFactor: 0.34),
            const SizedBox(height: ProfileSectionHeader.gap),
            Padding(
              padding: ProfileSectionHeader.sidePadding,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: AppRadius.large,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var i = 0; i < chipCount; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm + 4,
                            vertical: AppSpacing.xs + 2,
                          ),
                          child: SkeletonLine(
                            style: texts.labelLarge,
                            width: constraints.maxWidth *
                                _chipFactors[i % _chipFactors.length],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
