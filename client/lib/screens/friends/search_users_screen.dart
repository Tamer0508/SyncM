import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/friend.dart';
import '../../providers/friends_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/tappable_avatar.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key, this.embedded = false, this.onBack});

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _controller = TextEditingController();
  final _searchSubject = PublishSubject<String>();
  late final StreamSubscription<void> _searchSubscription;

  List<Friend> _results = [];
  bool _loading = false;
  bool _searched = false;

  final Set<String> _sentTo = {};

  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _searchSubscription = _searchSubject
        .debounceTime(const Duration(milliseconds: 350))
        .distinct()
        .switchMap(
          (query) => Stream.fromFuture(_search(query))
              .onErrorResume((_, _) => Stream<void>.empty()),
        )
        .listen((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _searchSubscription.cancel();
    _searchSubject.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _searched = false;
        _results = [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await context.read<FriendsProvider>().search(q);
      if (!mounted) return;
      setState(() {
        _searched = true;
        _results = results;
        _sentTo.clear();
      });
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendRequest(Friend user) async {
    if (_pending.contains(user.id) || _sentTo.contains(user.id)) return;

    setState(() => _pending.add(user.id));
    try {
      await context.read<FriendsProvider>().sendRequest(user.id);
      if (!mounted) return;
      setState(() => _sentTo.add(user.id));
      showSuccess(context, 'Заявка отправлена');
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _pending.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: _controller,
            autofocus: !widget.embedded,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Имя пользователя',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Очистить',
                      onPressed: () {
                        _controller.clear();
                        _searchSubject.add('');
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (value) {
              _searchSubject.add(value);
              // Перерисовка нужна, чтобы крестик появлялся и исчезал.
              setState(() {});
            },
            onSubmitted: _search,
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.short,
            child: _buildResults(),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Поиск друзей')),
      body: body,
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
    }

    if (!_searched) {
      return _SearchPlaceholder(
        key: const ValueKey('idle'),
        icon: Icons.person_search_rounded,
        title: 'Найдите друзей',
        subtitle: 'Введите имя пользователя, чтобы начать поиск.',
      );
    }

    if (_results.isEmpty) {
      return _SearchPlaceholder(
        key: const ValueKey('empty'),
        icon: Icons.search_off_rounded,
        title: 'Никого не нашлось',
        subtitle: 'Проверьте написание имени или попробуйте другое.',
      );
    }

    return ListView.separated(
      key: const ValueKey('results'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final user = _results[i];
        return _UserTile(
          user: user,
          isPending: _pending.contains(user.id),
          isSent: _sentTo.contains(user.id),
          onSend: () => _sendRequest(user),
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isPending,
    required this.isSent,
    required this.onSend,
  });

  final Friend user;
  final bool isPending;
  final bool isSent;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          TappableAvatar(
            imageUrl: user.avatarUrl,
            radius: 24,
            title: user.name,
            heroTag: 'search-${user.id}',
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              user.name,
              style: texts.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ActionButton(
            status: user.friendshipStatus,
            isPending: isPending,
            isSent: isSent,
            onSend: onSend,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.status,
    required this.isPending,
    required this.isSent,
    required this.onSend,
  });

  final FriendshipStatus status;
  final bool isPending;
  final bool isSent;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    if (isPending) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    Widget label(String text, {IconData? icon, Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color ?? colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              text,
              style: texts.labelMedium?.copyWith(color: color ?? colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (isSent || status == FriendshipStatus.sent) {
      return label('Отправлено', icon: Icons.schedule_rounded);
    }

    switch (status) {
      case FriendshipStatus.friends:
        return label('В друзьях', icon: Icons.check_rounded, color: colors.primary);
      case FriendshipStatus.received:
        return label('Ждёт ответа', icon: Icons.mark_email_unread_rounded);
      case FriendshipStatus.none:
      case FriendshipStatus.sent:
        return IconButton.filledTonal(
          onPressed: onSend,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          tooltip: 'Отправить заявку',
          visualDensity: VisualDensity.compact,
        );
    }
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: colors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: texts.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}