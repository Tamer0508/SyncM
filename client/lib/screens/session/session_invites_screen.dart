import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/skeleton.dart';

class SessionInvitesScreen extends StatefulWidget {
  const SessionInvitesScreen({super.key, this.embedded = false, this.onBack});

  /// Встроенный режим: экран занимает лишь центральную часть главного,
  /// поэтому своя шапка не нужна — над ним уже есть шапка главного экрана.
  final bool embedded;

  /// Как вернуться из встроенного вида.
  final VoidCallback? onBack;

  @override
  State<SessionInvitesScreen> createState() => _SessionInvitesScreenState();
}

class _SessionInvitesScreenState extends State<SessionInvitesScreen> {
  final Set<String> _responding = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<SessionProvider>();
      prov.markInvitesAsRead();
      prov.fetchInvites();
    });
  }

  Future<void> _respond(String sessionId, bool accept) async {
    if (_responding.contains(sessionId)) return;
    setState(() => _responding.add(sessionId));

    try {
      final result = await context.read<SessionProvider>().respondToInvite(sessionId, accept);
      if (!mounted) return;

      if (result == null) {
        showError(context, 'Не удалось ответить на приглашение', force: true);
        return;
      }

      if (!accept) {
        showSuccess(context, 'Приглашение отклонено');
        return;
      }

      final session = result['session'] as Map<String, dynamic>?;
      if (session != null) {
        // На широком экране просим показать сессию встроенной, а не
        // открываем маршрутом: иначе она занимала бы весь экран, закрывая
        // боковую панель и панель воспроизведения. При повторном заходе с
        // главной та же сессия показывалась встроенной — из-за этого одна и
        // та же сессия выглядела по-разному в зависимости от пути входа.
        if (context.isWideWindow) {
          context.read<SessionProvider>().requestOpenSession(session);
          Navigator.of(context).maybePop();
          return;
        }
        Navigator.of(context).pushReplacementNamed('/session', arguments: session);
      } else {
        // Сессия принята, но данных для перехода нет — сообщаем об этом
        // вместо молчания: раньше экран просто оставался на месте, и было
        // непонятно, сработало ли нажатие.
        showSuccess(context, 'Вы присоединились к сессии');
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    } finally {
      if (mounted) setState(() => _responding.remove(sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {

    final body = Consumer<SessionProvider>(
      builder: (context, prov, _) {
        if (prov.invitesLoading && prov.invites.isEmpty) {
          return const SingleChildScrollView(child: SkeletonList(itemCount: 4));
        }

        if (prov.invites.isEmpty) {
          // Пустое состояние внутри прокручиваемой области: иначе жест
          // обновления по нему не срабатывает. Прежний расчёт высоты через
          // MediaQuery минус kToolbarHeight давал переполнение на невысоких
          // экранах с открытой клавиатурой.
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 80), _EmptyInvitesView()],
          );
        }

        return _InvitesList(
          invites: prov.invites,
          hostNameForInvite: prov.hostNameForInvite,
          responding: _responding,
          onAccept: (id) => _respond(id, true),
          onDecline: (id) => _respond(id, false),
        );
      },
    );

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: 'Приглашения',
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Обновить',
            onPressed: () =>
                context.read<SessionProvider>().fetchInvites(),
          ),
        ],
      ),
      child: body,
    );
  }
}

class _EmptyInvitesView extends StatelessWidget {
  const _EmptyInvitesView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mail_outline_rounded,
            size: 72,
            color: colors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Приглашений нет', style: texts.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Когда друг позовёт вас слушать музыку вместе, приглашение появится здесь.',
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InvitesList extends StatelessWidget {
  const _InvitesList({
    required this.invites,
    required this.hostNameForInvite,
    required this.responding,
    required this.onAccept,
    required this.onDecline,
  });

  final List<Map<String, dynamic>> invites;
  final String? Function(Map<String, dynamic>) hostNameForInvite;
  final Set<String> responding;
  final void Function(String sessionId) onAccept;
  final void Function(String sessionId) onDecline;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: invites.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm + 4),
      itemBuilder: (context, i) {
        final invite = invites[i];
        final sessionId = invite['id'] as String;

        return _InviteCard(
          sessionName: invite['name'] as String? ?? 'Сессия',
          hostName: hostNameForInvite(invite) ?? 'Друг',
          trackCount: (invite['tracks'] as List?)?.length ?? 0,
          isResponding: responding.contains(sessionId),
          onAccept: () => onAccept(sessionId),
          onDecline: () => onDecline(sessionId),
        );
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.sessionName,
    required this.hostName,
    required this.trackCount,
    required this.isResponding,
    required this.onAccept,
    required this.onDecline,
  });

  final String sessionName;
  final String hostName;
  final int trackCount;
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: AppRadius.small,
                ),
                child: Icon(Icons.headphones_rounded, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionName,
                      style: texts.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'От $hostName',
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (trackCount > 0) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            // Количество треков помогает решить, стоит ли присоединяться:
            // пустая сессия и сессия с готовой подборкой — разные приглашения.
            Row(
              children: [
                Icon(Icons.queue_music_rounded, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '$trackCount ${_plural(trackCount)}',
                  style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isResponding ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                  ),
                  child: const Text('Отклонить'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: FilledButton(
                  onPressed: isResponding ? null : onAccept,
                  child: isResponding
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            // Цвет из палитры, а не белый: на светлой теме
                            // белый индикатор на кнопке почти не виден.
                            color: colors.onPrimary,
                          ),
                        )
                      : const Text('Принять'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Склонение слова «трек» по числу.
  String _plural(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'треков';
    return switch (count % 10) {
      1 => 'трек',
      2 || 3 || 4 => 'трека',
      _ => 'треков',
    };
  }
}