import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../providers/session_provider.dart';
import '../../models/friend.dart';
import '../../utils/notifications.dart';

class CreateSessionScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onCancel;
  final ValueChanged<Map<String, dynamic>>? onSessionCreated;

  const CreateSessionScreen(
      {Key? key, this.embedded = false, this.onCancel, this.onSessionCreated})
      : super(key: key);

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _nameController = TextEditingController();
  Friend? _selectedFriend;
  bool _creating = false;
  String? _nameError;

  bool get _nameValid =>
      _nameController.text.trim().isNotEmpty &&
      _nameController.text.trim().length >= 2 &&
      _nameController.text.trim().length <= 100 &&
      _validNameChars.hasMatch(_nameController.text.trim());
  static final _validNameChars = RegExp(r'^[а-яА-ЯёЁa-zA-Z0-9 ._\-()]+$');

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FriendsProvider>(context, listen: false)
          .fetchFriends(refresh: true);
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_validateName);
    _nameController.dispose();
    super.dispose();
  }

  void _validateName() {
    final text = _nameController.text.trim();
    setState(() {
      if (text.isEmpty)
        _nameError = 'Название не может быть пустым';
      else if (text.length < 2)
        _nameError = 'Минимум 2 символа';
      else if (text.length > 100)
        _nameError = 'Не более 100 символов';
      else if (!_validNameChars.hasMatch(text))
        _nameError = 'Только буквы, цифры, пробелы и ._-()';
      else
        _nameError = null;
    });
  }

  bool get _canSubmit => _nameValid && _selectedFriend != null;

  Future<void> _create() async {
    if (!_canSubmit) return;
    final name = _nameController.text.trim();
    setState(() => _creating = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final session = await api.createSession(name, _selectedFriend!.id);
      if (session != null && mounted) {
        if (widget.onSessionCreated != null) {
          widget.onSessionCreated!(session);
        } else {
          Navigator.of(context)
              .pushReplacementNamed('/session', arguments: session);
        }
      }
    } catch (e) {
      if (mounted)
        showAppNotification(context,
            message: 'Ошибка: $e', type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friends = Provider.of<FriendsProvider>(context).friends;
    final colorScheme = theme.colorScheme;

    final body = SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            margin: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.embedded) ...[
                        Text('Новая музыкальная сессия',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                            'Пригласите друга и слушайте музыку вместе в реальном времени.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodySmall?.color
                                    ?.withOpacity(0.78),
                                height: 1.5)),
                        const SizedBox(height: 24),
                      ],
                      TextField(
                        controller: _nameController,
                        maxLength: 100,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[а-яА-ЯёЁa-zA-Z0-9 ._\-()]'))
                        ],
                        decoration: InputDecoration(
                            labelText: 'Название сессии',
                            counterText: '',
                            errorText: _nameError,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                    color: _nameError != null
                                        ? colorScheme.error
                                        : colorScheme.primary,
                                    width: 2)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                    color: _nameError != null
                                        ? colorScheme.error
                                        : colorScheme.outline))),
                        onChanged: (_) => _validateName(),
                      ),
                      const SizedBox(height: 24),
                      Text('Выберите друга',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (friends.isEmpty)
                        Center(
                            child: Text('Нет друзей',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.6))))
                      else ...[
                        ...friends.map((f) => _FriendSelectTile(
                            friend: f,
                            selected: _selectedFriend?.id == f.id,
                            onTap: () => setState(() => _selectedFriend = f))),
                        if (_selectedFriend == null)
                          Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text('Обязательно выберите друга',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.error, fontSize: 12))),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _creating || !_canSubmit ? null : _create,
                        style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: _canSubmit
                                ? colorScheme.primary
                                : colorScheme.surfaceVariant,
                            foregroundColor: _canSubmit
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface.withOpacity(0.38)),
                        child: _creating
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Создать сессию'),
                      ),
                    ]))));

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Создать сессию'),
          leading: widget.onCancel != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onCancel)
              : null),
      body: SafeArea(child: body),
    );
  }
}

class _FriendSelectTile extends StatelessWidget {
  final Friend friend;
  final bool selected;
  final VoidCallback onTap;
  const _FriendSelectTile(
      {required this.friend, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color:
                      selected ? theme.colorScheme.primary : Colors.transparent,
                  width: 2)),
          child: Row(children: [
            CircleAvatar(
                radius: 20,
                backgroundImage:
                    friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty
                        ? NetworkImage(friend.avatarUrl!)
                        : null,
                backgroundColor: theme.colorScheme.surfaceVariant,
                child: friend.avatarUrl == null || friend.avatarUrl!.isEmpty
                    ? Icon(Icons.person,
                        color: theme.colorScheme.primary, size: 20)
                    : null),
            const SizedBox(width: 12),
            Expanded(
                child: Text(friend.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600))),
            if (selected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ])),
    );
  }
}
