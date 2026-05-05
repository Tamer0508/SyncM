import 'package:flutter/material.dart';
import '../../widgets/track_card.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({Key? key}) : super(key: key);

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  List<Map<String, dynamic>> _tracks = [];

  @override
  void initState() {
    super.initState();
    // В реальном приложении здесь загружаются треки сессии
  }

  void _rate(String trackId, int rating) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Голос сохранён')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Сессия')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _tracks.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Сессия пока пуста', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('Добавьте треки или начните новую музыкальную встречу.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78))),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _tracks.length,
                itemBuilder: (_, i) {
                  final t = _tracks[i];
                  return TrackCard(
                    id: t['id'] ?? 'unknown',
                    title: t['trackName'] ?? t['name'] ?? 'Track',
                    artist: t['artistName'] ?? t['artist'] ?? 'Artist',
                    isLiked: (t['liked'] ?? false) as bool,
                    onLike: () => _rate(t['id'] ?? '', 1),
                  );
                },
              ),
      ),
    );
  }
}
