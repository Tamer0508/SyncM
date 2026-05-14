import 'package:flutter/material.dart';
import '../../widgets/interactive_card.dart';

class SessionResultsScreen extends StatelessWidget {
  const SessionResultsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Результаты сессии')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InteractiveCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Результаты', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text('Здесь будут отображаться итоговые треки, оценки и подробные метрики сессии.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                children: [
                  InteractiveCard(
                    borderRadius: 22,
                    margin: const EdgeInsets.only(bottom: 0),
                    child: ListTile(
                      title: Text('Трек 1', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Собран 4.7 из 5'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InteractiveCard(
                    borderRadius: 22,
                    margin: const EdgeInsets.only(bottom: 0),
                    child: ListTile(
                      title: Text('Трек 2', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Собран 4.5 из 5'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
