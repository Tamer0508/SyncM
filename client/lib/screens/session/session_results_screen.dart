import 'package:flutter/material.dart';

class SessionResultsScreen extends StatelessWidget {
  const SessionResultsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final mutualLikes = args?['mutualLikes'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Результаты сессии')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Общие любимые треки 🎵',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      mutualLikes.isEmpty
                          ? 'На этот раз общих треков не нашлось.'
                          : 'Вам обоим понравились эти треки!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.78)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: mutualLikes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_off, size: 64, color: theme.colorScheme.primary.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text('Нет общих треков',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemCount: mutualLikes.length,
                      itemBuilder: (_, i) {
                        final t = mutualLikes[i];
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: ListTile(
                            leading: const Icon(Icons.favorite, color: Colors.red),
                            title: Text(t['trackName'] ?? '',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            subtitle: Text(t['artistName'] ?? ''),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('На главную'),
            ),
          ],
        ),
      ),
    );
  }
}