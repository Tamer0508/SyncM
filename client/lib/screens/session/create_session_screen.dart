import 'package:flutter/material.dart';

class CreateSessionScreen extends StatelessWidget {
  const CreateSessionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Создать сессию')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Новая музыкальная сессия', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(
                    'Запланируйте совместное прослушивание, пригласите друзей и создайте атмосферу для новых открытий.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78), height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Название сессии',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Описание',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Создать сессию'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
