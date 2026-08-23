import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playlists_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../utils/error_utils.dart';
import 'app_bottom_sheet.dart';
import 'playlist_actions.dart';

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  Map<String, dynamic> track,
) async {
  final uri = track['uri'] as String?;
  if (uri == null || uri.isEmpty) return;

  final playlists = context.read<PlaylistsProvider>();

  if (playlists.custom.isEmpty && !playlists.loadingCustom) {
    playlists.loadCustom().ignore();
  }

  await showAppSheet<void>(
    context: context,
    title: L.of(context).addToPlaylistTitle,
    builder: (_) => _AddToPlaylistBody(track: track),
  );
}

class _AddToPlaylistBody extends StatelessWidget {
  const _AddToPlaylistBody({required this.track});

  final Map<String, dynamic> track;

  Future<void> _addTo(
    BuildContext context,
    Map<String, dynamic> playlist,
  ) async {
    final playlists = context.read<PlaylistsProvider>();
    final navigator = Navigator.of(context);

    try {
      final result = await playlists.addTracks(playlist.playlistId, [
        {
          'trackUri': track['uri'],
          'trackName': track['name'],
          'artistName': track['artist'] ?? '',
          'imageUrl': track['imageUrl'],
          'durationMs': track['durationMs'],
        }
      ]);

      navigator.pop();
      if (!context.mounted) return;

      showSuccess(
        context,
        result.added > 0
            ? L.of(context).addedToPlaylist(playlist.playlistName)
            : L.of(context).alreadyInPlaylist(playlist.playlistName),
      );
    } catch (err) {
      navigator.pop();
      if (context.mounted) showError(context, err);
    }
  }

  Future<void> _createAndAdd(BuildContext context) async {
    final navigator = Navigator.of(context);
    final created = await showCreatePlaylistDialog(context);
    if (created == null) {
      navigator.pop();
      return;
    }
    if (!context.mounted) return;
    await _addTo(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistsProvider>();
    final custom = playlists.custom;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (custom.isEmpty && playlists.loadingCustom)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (custom.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                L.of(context).addToPlaylistEmpty,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final playlist in custom)
              ListTile(
                leading: Icon(
                  Icons.queue_music_rounded,
                  color: context.colors.onSurfaceVariant,
                ),
                title: Text(
                  playlist.playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _trackCountLabel(context, playlist.playlistTrackCount),
                  style: context.texts.bodySmall,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                onTap: () => _addTo(context, playlist),
              ),
          const Divider(
            height: AppSpacing.md,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
          ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: context.colors.primary),
            title: Text(
              L.of(context).addToPlaylistCreate,
              style: context.texts.bodyLarge?.copyWith(color: context.colors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            onTap: () => _createAndAdd(context),
          ),
        ],
      ),
    );
  }

  String _trackCountLabel(BuildContext context, int count) {
    if (count == 0) return L.of(context).commonEmpty;
    return L.of(context).trackCount(count);
  }
}
