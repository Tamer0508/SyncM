import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/session_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../l10n/app_localizations.dart';
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
    this.onFindFriends,
  });

  final bool embedded;
  final VoidCallback? onCancel;
  final ValueChanged<Map<String, dynamic>>? onSessionCreated;

  final VoidCallback? onFindFriends;

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  static final _validNameChars = RegExp(r'^[а-яА-ЯёЁa-zA-Z0-9 ._\-()]+$');
  static const _maxNameLength = 100;

  final _nameController = TextEditingController();

  final _friendSearchController = TextEditingController();
  String _friendQuery = '';
  Friend? _selectedFriend;
  bool _creating = false;

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
    _friendSearchController.dispose();
    super.dispose();
  }

  String get _name => _nameController.text.trim();

  void _openFriendSearch() {
    final custom = widget.onFindFriends;
    if (custom != null) {
      custom();
      return;
    }
    Navigator.of(context).pushNamed('/friends/search');
  }

  String? get _nameError {
    if (!_nameTouched) return null;
    if (_name.isEmpty) return L.of(context).playlistNameEmptyGeneric;
    if (_name.length < 2) return L.of(context).playlistNameTooShort;
    if (_name.length > _maxNameLength) {
      return L.of(context).nameDialogTooLong(_maxNameLength);
    }
    if (!_validNameChars.hasMatch(_name)) return L.of(context).playlistNameCharset;
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
        showError(context, L.of(context).createSessionFailed, force: true);
        return;
      }

      context.read<SessionProvider>().fetchMySessions().ignore();

      if (widget.onSessionCreated != null) {
        widget.onSessionCreated!(session);
      } else {
        if (context.isWideWindow) {
          context.read<SessionProvider>().requestOpenSession(session);
          unawaited(Navigator.of(context).maybePop());
          return;
        }
        unawaited(Navigator.of(context)
            .pushReplacementNamed('/session', arguments: session));
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
    final visibleFriends = _friendQuery.isEmpty
        ? friends
        : friends
            .where((f) => f.name.toLowerCase().contains(_friendQuery.toLowerCase()))
            .toList();
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
          L.of(context).createSessionHint,
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
            labelText: L.of(context).createSessionName,
            counterText: _name.length > _maxNameLength - 20 ? null : '',
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameTouched = true),
          onSubmitted: (_) => _canSubmit ? _create() : null,
        ),

        const SizedBox(height: AppSpacing.lg),
        Text(L.of(context).createSessionWithWhom, style: texts.titleMedium),
        const SizedBox(height: AppSpacing.sm + 4),

        if (friends.isEmpty)
          _NoFriendsHint(onFindFriends: _openFriendSearch)
        else ...[
          if (friends.length > 6) ...[
            TextField(
              controller: _friendSearchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: L.of(context).createSessionSearchFriends,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _friendQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: L.of(context).commonClear,
                        onPressed: () {
                          _friendSearchController.clear();
                          setState(() => _friendQuery = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _friendQuery = value.trim()),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          if (visibleFriends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                L.of(context).createSessionNobodyFound,
                style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final friend in visibleFriends)
                  _FriendChip(
                    friend: friend,
                    selected: _selectedFriend?.id == friend.id,
                    onTap: () => setState(() {
                      _selectedFriend =
                          _selectedFriend?.id == friend.id ? null : friend;
                    }),
                  ),
              ],
            ),
        ],

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
              : Text(L.of(context).homeStartSession),
          ),
        ),

        if (_nameValid && _selectedFriend == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            L.of(context).createSessionPickFriend,
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: L.of(context).navNewSession,
        onBack: widget.onCancel ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: body,
    );
  }
}

class _NoFriendsHint extends StatelessWidget {
  const _NoFriendsHint({required this.onFindFriends});

  final VoidCallback onFindFriends;

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
            L.of(context).createSessionFriendsOnly,
            style: texts.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            L.of(context).createSessionFriendsOnlyHint,
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onFindFriends,
            icon: const Icon(Icons.person_add_rounded),
            label: Text(L.of(context).navFindFriends),
          ),
        ],
      ),
    );
  }
}

class _FriendChip extends StatefulWidget {
  const _FriendChip({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  final Friend friend;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FriendChip> createState() => _FriendChipState();
}

class _FriendChipState extends State<_FriendChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final friend = widget.friend;

    final background = widget.selected
        ? colors.onSurface
        : (_pressed ? colors.surfaceContainerHighest : colors.surfaceContainerHigh);
    final foreground = widget.selected ? colors.surface : colors.onSurface;

    return AnimatedScale(
      scale: _pressed && !context.reduceMotion ? AppScale.control : 1.0,
      duration: AppMotion.press,
      curve: AppMotion.enter,
      child: Material(
        color: background,
        animationDuration: AppMotion.press,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs + 2,
              AppSpacing.xs + 2,
              AppSpacing.md,
              AppSpacing.xs + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TappableAvatar(
                  imageUrl: friend.avatarUrl,
                  radius: 16,
                  title: friend.name,
                  onTapOverride: widget.onTap,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  friend.name,
                  style: texts.labelLarge?.copyWith(color: foreground),
                ),
                if (friend.showsPresence && friend.isOnline) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.brand.online,
                    ),
                  ),
                ],
                if (widget.selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.check_rounded, size: 18, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}