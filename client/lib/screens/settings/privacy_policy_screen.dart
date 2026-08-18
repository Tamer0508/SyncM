import 'package:flutter/material.dart';

import '../../config.dart';
import '../../theme.dart';
import '../../widgets/screen_chrome.dart';
import 'legal_document_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({
    super.key,
    this.embedded = false,
    this.onBack,
    this.onOpenFullText,
  });

  final bool embedded;
  final VoidCallback? onBack;

  final VoidCallback? onOpenFullText;

  static const _stored = <({IconData icon, String title, String detail})>[
    (
      icon: Icons.person_outline_rounded,
      title: 'Профиль',
      detail: 'Имя, адрес почты и аватар. Почта нужна для входа, '
          'имя и аватар видят друзья.',
    ),
    (
      icon: Icons.people_outline_rounded,
      title: 'Друзья и заявки',
      detail: 'С кем вы дружите и кому отправляли заявки. '
          'Заблокированные хранятся отдельно и никому не показываются.',
    ),
    (
      icon: Icons.headphones_outlined,
      title: 'Сессии',
      detail: 'Названия совместных прослушиваний, их участники, добавленные '
          'треки и оценки — чтобы показать совпадения в конце.',
    ),
    (
      icon: Icons.history_rounded,
      title: 'История прослушанного',
      detail: 'Треки, которые вы включали в приложении, и время. '
          'Её можно очистить в разделе «Данные».',
    ),
    (
      icon: Icons.music_note_outlined,
      title: 'Подключение Spotify',
      detail: 'Идентификатор аккаунта и токены доступа — в зашифрованном '
          'виде. Пароль от Spotify приложение не видит и не получает.',
    ),
  ];

  static const _notStored = <String>[
    'Пароль от Spotify — авторизация проходит на стороне Spotify.',
    'Содержимое прослушивания вне приложения: что вы слушаете сами, '
        'без сессии, никуда не отправляется.',
    'Платёжные данные — приложение бесплатное и ничего не принимает.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return ScreenChrome(
      embedded: embedded,
      header: ScreenHeader(
        title: 'Данные и приватность',
        onBack: onBack ?? (embedded ? null : () => Navigator.of(context).pop()),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          // Ширину ограничиваем: на широком экране строка в полторы тысячи
          // точек не читается.
          Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSizes.readableWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Что хранится',
                    style: texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Список собран по тому, что приложение действительно '
                    'записывает в базу.',
                    style: texts.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final item in _stored) ...[
                    _DataRow(
                      icon: item.icon,
                      title: item.title,
                      detail: item.detail,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text('Чего нет', style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final line in _notStored) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(Icons.remove_rounded,
                              size: 14, color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            line,
                            style: texts.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text('Как удалить', style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'История прослушанного очищается в разделе «Данные». '
                    'Там же удаляется аккаунт целиком — вместе с профилем, '
                    'друзьями, сессиями и подключением Spotify. Это '
                    'необратимо.',
                    style: texts.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Полный текст', style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Всё написанное выше — краткий пересказ. Полная политика '
                    'конфиденциальности с формулировками и сроками хранения '
                    'открывается ниже.',
                    style: texts.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onOpenFullText ??
                        () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentScreen(
                                  title: 'Политика конфиденциальности',
                                  assetPath: Config.privacyPolicyAsset,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('Политика конфиденциальности'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.medium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: texts.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}