import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/playlists_provider.dart';
import '../screens/playlist/add_tracks_screen.dart';
import '../screens/settings/avatar_crop_screen.dart';
import '../theme.dart';
import '../utils/error_utils.dart';
import '../utils/notifications.dart';
import 'app_menu.dart';

enum PlaylistAction {
  open,
  addMusic,
  edit,
  cover,
  removeCover,
  share,
  duplicate,
  clear,
  delete,
}

List<AppMenuEntry<PlaylistAction>> playlistMenuEntries(
  Map<String, dynamic> playlist, {
  bool includeOpen = true,
}) {
  final isCustom = playlist.isCustomPlaylist;
  final hasTracks = playlist.playlistTrackCount > 0;
  final hasCover = playlist.playlistImageUrl != null;

  return [
    if (includeOpen)
      const AppMenuEntry(
        value: PlaylistAction.open,
        icon: Icons.play_circle_outline_rounded,
        label: 'Открыть',
      ),
    if (isCustom) ...[
      const AppMenuEntry(
        value: PlaylistAction.addMusic,
        icon: Icons.library_add_rounded,
        label: 'Добавить музыку',
      ),
      const AppMenuEntry(
        value: PlaylistAction.edit,
        icon: Icons.edit_outlined,
        label: 'Изменить название и описание',
      ),
      const AppMenuEntry(
        value: PlaylistAction.cover,
        icon: Icons.image_outlined,
        label: 'Изменить обложку',
      ),
      if (hasCover)
        const AppMenuEntry(
          value: PlaylistAction.removeCover,
          icon: Icons.hide_image_outlined,
          label: 'Убрать обложку',
        ),
    ],
    const AppMenuEntry(
      value: PlaylistAction.share,
      icon: Icons.ios_share_rounded,
      label: 'Поделиться',
    ),
    if (isCustom) ...[
      const AppMenuEntry(
        value: PlaylistAction.duplicate,
        icon: Icons.copy_all_outlined,
        label: 'Дублировать',
      ),
      // Дальше — необратимое. Черта здесь не украшение: очистка и удаление
      // отличаются от переименования последствиями, а не оттенком текста.
      if (hasTracks)
        const AppMenuEntry(
          value: PlaylistAction.clear,
          icon: Icons.playlist_remove_rounded,
          label: 'Очистить плейлист',
          danger: true,
          separated: true,
        ),
      AppMenuEntry(
        value: PlaylistAction.delete,
        icon: Icons.delete_outline_rounded,
        label: 'Удалить плейлист',
        danger: true,
        separated: !hasTracks,
      ),
    ],
  ];
}

Future<void> runPlaylistAction(
  BuildContext context,
  PlaylistAction action,
  Map<String, dynamic> playlist, {
  VoidCallback? onOpen,
  VoidCallback? onDeleted,
  VoidCallback? onTracksChanged,
}) async {
  final playlists = context.read<PlaylistsProvider>();
  final id = playlist.playlistId;

  try {
    switch (action) {
      case PlaylistAction.open:
        onOpen?.call();

      case PlaylistAction.addMusic:
        final changed = await AddTracksScreen.open(context, playlist);
        if (changed == true) onTracksChanged?.call();

      case PlaylistAction.edit:
        final result = await showPlaylistEditDialog(context, playlist);
        if (result == null) return;
        await playlists.edit(
          id,
          name: result.name,
          description: result.description,
          clearDescription: result.description.isEmpty,
        );

      case PlaylistAction.cover:
        await _pickAndUploadCover(context, playlist);

      case PlaylistAction.removeCover:
        await playlists.removeCover(id);
        if (context.mounted) showSuccess(context, 'Обложка убрана');

      case PlaylistAction.share:
        await _sharePlaylist(context, playlist);

      case PlaylistAction.duplicate:
        final copy = await playlists.duplicate(id);
        if (context.mounted) {
          showSuccess(context, 'Создана копия «${copy.playlistName}»');
        }

      case PlaylistAction.clear:
        final confirmed = await _confirm(
          context,
          title: 'Очистить плейлист?',
          message: 'Из «${playlist.playlistName}» будут удалены все треки. '
              'Сам плейлист останется.',
          confirmLabel: 'Очистить',
        );
        if (confirmed != true) return;
        await playlists.clearTracks(id);
        onTracksChanged?.call();
        if (context.mounted) showSuccess(context, 'Плейлист очищен');

      case PlaylistAction.delete:
        final confirmed = await _confirm(
          context,
          title: 'Удалить плейлист?',
          message: '«${playlist.playlistName}» и его список треков будут '
              'удалены. Сами треки останутся в Spotify.',
          confirmLabel: 'Удалить',
        );
        if (confirmed != true) return;
        await playlists.delete(id);
        onDeleted?.call();
        if (context.mounted) showSuccess(context, 'Плейлист удалён');
    }
  } catch (err) {
    if (context.mounted) showError(context, err);
  }
}

class PlaylistActionsButton extends StatelessWidget {
  const PlaylistActionsButton({
    super.key,
    required this.playlist,
    this.includeOpen = true,
    this.onOpen,
    this.onDeleted,
    this.onTracksChanged,
    this.iconColor,
  });

  final Map<String, dynamic> playlist;
  final bool includeOpen;
  final VoidCallback? onOpen;
  final VoidCallback? onDeleted;
  final VoidCallback? onTracksChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return AppMenuButton<PlaylistAction>(
      iconColor: iconColor ?? context.colors.onSurfaceVariant,
      tooltip: 'Действия с плейлистом',
      entries: playlistMenuEntries(playlist, includeOpen: includeOpen),
      onSelected: (action) => runPlaylistAction(
        context,
        action,
        playlist,
        onOpen: onOpen,
        onDeleted: onDeleted,
        onTracksChanged: onTracksChanged,
      ),
    );
  }
}

class PlaylistContextMenuRegion extends StatelessWidget {
  const PlaylistContextMenuRegion({
    super.key,
    required this.playlist,
    required this.child,
    this.onOpen,
    this.onDeleted,
    this.onTracksChanged,
  });

  final Map<String, dynamic> playlist;
  final Widget child;
  final VoidCallback? onOpen;
  final VoidCallback? onDeleted;
  final VoidCallback? onTracksChanged;

  @override
  Widget build(BuildContext context) {
    if (!context.isWideWindow) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) async {
        final action = await showAppContextMenu<PlaylistAction>(
          context: context,
          globalPosition: details.globalPosition,
          entries: playlistMenuEntries(playlist),
        );
        if (action == null || !context.mounted) return;
        await runPlaylistAction(
          context,
          action,
          playlist,
          onOpen: onOpen,
          onDeleted: onDeleted,
          onTracksChanged: onTracksChanged,
        );
      },
      child: child,
    );
  }
}

const int kPlaylistNameMaxLength = 50;
final RegExp kPlaylistNameAllowed = RegExp(r'^[а-яА-ЯёЁa-zA-Z0-9 ._\-()]+$');

String? validatePlaylistName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Название не может быть пустым';
  if (trimmed.length < 2) return 'Минимум 2 символа';
  if (trimmed.length > kPlaylistNameMaxLength) {
    return 'Не более $kPlaylistNameMaxLength символов';
  }
  if (!kPlaylistNameAllowed.hasMatch(trimmed)) {
    return 'Только буквы, цифры, пробелы и ._-()';
  }
  return null;
}

typedef PlaylistDraft = ({String name, String description});

Future<Map<String, dynamic>?> showCreatePlaylistDialog(BuildContext context) async {
  final draft = await _showPlaylistForm(
    context,
    title: 'Новый плейлист',
    icon: Icons.playlist_add_rounded,
    submitLabel: 'Создать',
  );
  if (draft == null || !context.mounted) return null;

  try {
    final created = await context.read<PlaylistsProvider>().create(
          draft.name,
          description: draft.description.isEmpty ? null : draft.description,
        );
    return created;
  } catch (err) {
    if (context.mounted) showError(context, err);
    return null;
  }
}

Future<PlaylistDraft?> showPlaylistEditDialog(
  BuildContext context,
  Map<String, dynamic> playlist,
) {
  return _showPlaylistForm(
    context,
    title: 'Изменить плейлист',
    icon: Icons.edit_outlined,
    submitLabel: 'Сохранить',
    initialName: playlist.playlistName,
    initialDescription: playlist.playlistDescription,
  );
}

Future<PlaylistDraft?> _showPlaylistForm(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String submitLabel,
  String initialName = '',
  String initialDescription = '',
}) {
  final nameController = TextEditingController(text: initialName);
  final descriptionController = TextEditingController(text: initialDescription);
  var nameError = validatePlaylistName(initialName);

  return showDialog<PlaylistDraft>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void submit() {
          if (nameError != null) return;
          Navigator.of(ctx).pop((
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
          ));
        }

        return AlertDialog(
          icon: Icon(icon),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: kPlaylistNameMaxLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[а-яА-ЯёЁa-zA-Z0-9 ._\-()]'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Название',
                  counterText: '',
                  errorText: nameError,
                ),
                onChanged: (value) => setDialogState(
                  () => nameError = validatePlaylistName(value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: descriptionController,
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Необязательно',
                  counterText: '',
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: nameError == null ? submit : null,
              child: Text(submitLabel),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: context.colors.error),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.error,
            foregroundColor: context.colors.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}


Future<void> _pickAndUploadCover(
  BuildContext context,
  Map<String, dynamic> playlist,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true, // получаем bytes сразу (работает и на мобильных)
    allowMultiple: false,
  );

  if (result == null || result.files.isEmpty) return;
  final file = result.files.first;

  const allowed = ['png', 'jpg', 'jpeg', 'gif', 'webp'];
  final ext = (file.extension ?? '').toLowerCase();
  if (!allowed.contains(ext)) {
    if (!context.mounted) return;
    showAppNotification(
      context,
      message: 'Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
      type: NotificationType.error,
    );
    return;
  }

  final bytes = file.bytes;
  if (bytes == null) {
    if (!context.mounted) return;
    showAppNotification(
      context,
      message: 'Не удалось прочитать файл',
      type: NotificationType.error,
    );
    return;
  }

  if (!context.mounted) return;

  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => AvatarCropScreen(
        imageBytes: bytes,
        title: 'Обложка плейлиста',
        hint: 'Обложка квадратная — так плейлисты выглядят ровно в списке.',
      ),
      fullscreenDialog: true,
    ),
  );

  if (cropped == null || !context.mounted) return;

  final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.png';
  await context.read<PlaylistsProvider>().setCover(
        playlist.playlistId,
        cropped,
        fileName,
      );

  if (context.mounted) showSuccess(context, 'Обложка обновлена');
}

Future<void> _sharePlaylist(
  BuildContext context,
  Map<String, dynamic> playlist,
) async {
  final playlists = context.read<PlaylistsProvider>();

  final tracks = await playlists.tracksOf(
    playlist.playlistId,
    isCustom: playlist.isCustomPlaylist,
  );

  final buffer = StringBuffer(playlist.playlistName);
  final description = playlist.playlistDescription;
  if (description.isNotEmpty) buffer.write('\n$description');

  if (tracks != null && tracks.isNotEmpty) {
    buffer.write('\n');
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final name = track['name'] as String? ?? '';
      final artist = track['artist'] as String? ?? '';
      buffer.write('\n${i + 1}. $name${artist.isEmpty ? '' : ' — $artist'}');
    }
  }

  await Clipboard.setData(ClipboardData(text: buffer.toString()));
  if (context.mounted) showSuccess(context, 'Плейлист скопирован в буфер обмена');
}
