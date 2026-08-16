import 'package:flutter/material.dart';
import '../../providers/session_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/tappable_avatar.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({
    super.key,
    this.embedded = false,
    this.onCancel,
    this.onSessionCreated,
  });

  final bool embedded;
  final VoidCallback? onCancel;
  final ValueChanged<Map<String, dynamic>>? onSessionCreated;

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  static final _validNameChars = RegExp(r'^[а-яА-ЯёЁa-zA-Z0-9 ._\-()]+$');
  static const _maxNameLength = 100;

  final _nameController = TextEditingController();
  Friend? _selectedFriend;
  bool _creating = false;

  /// Показывать ошибку названия только после первой попытки ввода.
  ///
  /// Раньше «Название не может быть пустым» появлялось сразу при открытии
  /// экрана — форма встречала пользователя ошибкой ещё до того, как он
  /// что-либо сделал.
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FriendsProvider>().fetchFriends(refresh: true);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _name => _nameController.text.trim();

  String? get _nameError {
    if (!_nameTouched) return null;
    if (_name.isEmpty) return 'Введите название';
    if (_name.length < 2) return 'Минимум 2 символа';
    if (_name.length > _maxNameLength) return 'Не более $_maxNameLength символов';
    if (!_validNameChars.hasMatch(_name)) return 'Только буквы, цифры, пробелы и ._-()';
    return null;
  }

  bool get _nameValid =>
      _name.length >= 2 && _name.length <= _maxNameLength && _validNameChars.hasMatch(_name);

  bool get _canSubmit => _nameValid && _selectedFriend != null && !_creating;

  Future<void> _create() async {
    if (!_canSubmit) return;

    setState(() => _creating = true);
    try {
      final api = context.read<AuthProvider>().api;
      final session = await api.createSession(_name, _selectedFriend!.id);
      if (!mounted) return;

      if (session == null) {
        showError(context, 'Не удалось создать сессию', force: true);
        return;
      }

      context.read<SessionProvider>().fetchMySessions().ignore();

      if (widget.onSessionCreated != null) {
        widget.onSessionCreated!(session);
      } else {
        if (MediaQuery.sizeOf(context).width >= 900) {
          context.read<SessionProvider>().requestOpenSession(session);
          Navigator.of(context).maybePop();
          return;
        }
        Navigator.of(context).pushReplacementNamed('/session', arguments: session);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsProvider>().friends;
    final colors = context.colors;
    final texts = context.texts;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Text(
          'Пригласите друга и слушайте музыку одновременно.',
          style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),

        TextField(
          controller: _nameController,
          maxLength: _maxNameLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[а-яА-ЯёЁa-zA-Z0-9 ._\-()]')),
          ],
          decoration: InputDecoration(
            labelText: 'Название сессии',
            // Счётчик показывается только у длинных названий: постоянное
            // «0/100» под пустым полем ничего не сообщает, но создаёт
            // ощущение ограничения.
            counterText: _name.length > _maxNameLength - 20 ? null : '',
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameTouched = true),
          onSubmitted: (_) => _canSubmit ? _create() : null,
        ),

        const SizedBox(height: AppSpacing.lg),
        Text('С кем слушаем', style: texts.titleMedium),
        const SizedBox(height: AppSpacing.sm + 4),

        if (friends.isEmpty)
          const _NoFriendsHint()
        else
          ...friends.map(
            (friend) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _FriendSelectTile(
                friend: friend,
                selected: _selectedFriend?.id == friend.id,
                onTap: () => setState(() {
                  // Повторное нажатие снимает выбор.
                  _selectedFriend = _selectedFriend?.id == friend.id ? null : friend;
                }),
              ),
            ),
          ),

        const SizedBox(height: AppSpacing.lg),
        Center(
          child: FilledButton(
          onPressed: _canSubmit ? _create : null,
          child: _creating
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                )
              : const Text('Начать сессию'),
          ),
        ),

        // Подсказка о том, чего не хватает, вместо постоянного текста ошибки
        // под списком друзей. Она появляется, только когда название уже
        // введено — иначе сбивала бы с толку на пустой форме.
        if (_nameValid && _selectedFriend == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Выберите друга, чтобы продолжить',
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: 'Новая сессия',
        onBack: widget.onCancel ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: body,
    );
  }
}

class _NoFriendsHint extends StatelessWidget {
  const _NoFriendsHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded, size: 44, color: colors.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm + 4),
          Text(
            'Сессию можно создать только с другом',
            style: texts.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Добавьте кого-нибудь в друзья, и он появится в этом списке.',
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          // Раньше здесь было просто «Нет друзей» без выхода из ситуации:
          // пользователь упирался в тупик и должен был сам догадаться, куда идти.
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Найти друзей'),
          ),
        ],
      ),
    );
  }
}

class _FriendSelectTile extends StatelessWidget {
  const _FriendSelectTile({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  final Friend friend;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: AppRadius.large,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.emphasized,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.large,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              TappableAvatar(
                imageUrl: friend.avatarUrl,
                radius: 22,
                title: friend.name,
                heroTag: 'create-session-${friend.id}',
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      style: texts.titleSmall?.copyWith(
                        color: selected ? colors.onPrimaryContainer : colors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Статус присутствия важен именно здесь: звать в сессию
                    // того, кто не в сети, обычно бессмысленно.
                    if (friend.showsPresence && friend.isOnline) ...[
                      const SizedBox(height: 2),
                      Text(
                        'В сети',
                        style: texts.bodySmall?.copyWith(color: context.brand.online),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}