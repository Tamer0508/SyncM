import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../providers/session_provider.dart';
import '../../models/friend.dart';
import '../../utils/notifications.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({Key? key}) : super(key: key);

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _nameController = TextEditingController();
  Friend? _selectedFriend;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FriendsProvider>(context, listen: false).fetchFriends(refresh: true);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
  if (_selectedFriend == null) {
    showAppNotification(context, message: 'Выберите друга', type: NotificationType.error);
    return;
  }
  if (_nameController.text.trim().isEmpty) {
    showAppNotification(context, message: 'Введите название сессии', type: NotificationType.error);
    return;
  }

  setState(() => _creating = true);
  try {
    // Используем api из AuthProvider где уже есть cookie
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    final session = await api.createSession(
      _nameController.text.trim(),
      _selectedFriend!.id,
    );

    if (session != null && mounted) {
      Navigator.of(context).pushReplacementNamed('/session', arguments: session);
    }
  } catch (e) {
    if (mounted) showAppNotification(context, message: 'Ошибка: $e', type: NotificationType.error);
  } finally {
    if (mounted) setState(() => _creating = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friends = Provider.of<FriendsProvider>(context).friends;

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
                  Text('Новая музыкальная сессия',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Пригласите друга и слушайте музыку вместе в реальном времени.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.78), height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Название сессии',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Выберите друга',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (friends.isEmpty)
                    Center(
                      child: Text('Нет друзей',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
                    )
                  else
                    ...friends.map((f) => _FriendSelectTile(
                          friend: f,
                          selected: _selectedFriend?.id == f.id,
                          onTap: () => setState(() => _selectedFriend = f),
                        )),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _creating ? null : _create,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _creating
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Создать сессию'),
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

class _FriendSelectTile extends StatelessWidget {
  final Friend friend;
  final bool selected;
  final VoidCallback onTap;

  const _FriendSelectTile({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.15) : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
                  ? NetworkImage(friend.avatarUrl!)
                  : null,
              backgroundColor: theme.colorScheme.surfaceVariant,
              child: friend.avatarUrl == null || friend.avatarUrl!.isEmpty
                  ? Icon(Icons.person, color: theme.colorScheme.primary, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(friend.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (selected) Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}