import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';
import '../../screens/player/now_playing.dart';
import '../../main.dart' show navigatorKey;

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pb = Provider.of<PlaybackProvider>(context);
    if (pb.currentTrack == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final track = pb.currentTrack!;
    final imageBytes = pb.currentImageBytes;
    final imageUrl = track['imageUrl'] as String?;

    return Container(
      height: 72,
      // Важно: фиксируем ширину, чтобы избежать бесконечных ограничений
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Левая часть: обложка + текст – открывает плеер
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                navigatorKey.currentState?.push(MaterialPageRoute(
                  builder: (_) => NowPlayingScreen(
                    title: track['title'] as String?,
                    artist: track['artist'] as String?,
                    artworkUrl: imageUrl,
                  ),
                ));
              },
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageBytes != null
                        ? Image.memory(imageBytes, width: 48, height: 48, fit: BoxFit.cover)
                        : imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('data:')
                            ? Image.network(imageUrl, width: 48, height: 48, fit: BoxFit.cover)
                            : Container(
                                width: 48,
                                height: 48,
                                color: theme.colorScheme.primary.withOpacity(0.2),
                                child: Icon(Icons.music_note, color: theme.colorScheme.primary),
                              ),
                  ),
                  const SizedBox(width: 12),
                  // Текстовая часть – используем Flexible, а не Expanded, чтобы избежать ошибок
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track['title'] ?? '',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track['artist'] ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Кнопки управления
          IconButton(
            icon: Icon(
              pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            onPressed: () => pb.togglePlay(),
          ),
          IconButton(
            icon: Icon(Icons.skip_next_rounded, size: 28, color: theme.colorScheme.onSurface),
            onPressed: () => pb.skipNext(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}