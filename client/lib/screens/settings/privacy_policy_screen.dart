import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/screen_chrome.dart';
import 'legal_document_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  PrivacyPolicyScreen({
    super.key,
    this.embedded = false,
    this.onBack,
    this.onOpenFullText,
  });

  final bool embedded;
  final VoidCallback? onBack;

  final VoidCallback? onOpenFullText;

  List<({IconData icon, String title, String detail})> _stored(BuildContext context) =>
      <({IconData icon, String title, String detail})>[
    (
      icon: Icons.person_outline_rounded,
      title: L.of(context).accountProfile,
      detail: L.of(context).privacyDocProfile,
    ),
    (
      icon: Icons.people_outline_rounded,
      title: L.of(context).privacyDocFriends,
      detail: L.of(context).privacyDocFriendsText,
    ),
    (
      icon: Icons.headphones_outlined,
      title: L.of(context).sectionSessions,
      detail: L.of(context).privacyDocSessionsText,
    ),
    (
      icon: Icons.history_rounded,
      title: L.of(context).privacyHistory,
      detail: L.of(context).privacyDocHistoryText,
    ),
    (
      icon: Icons.music_note_outlined,
      title: L.of(context).privacyDocSpotify,
      detail: L.of(context).privacyDocSpotifyText,
    ),
      ];

  List<String> _notStored(BuildContext context) => <String>[
    L.of(context).privacyDocNoPassword,
    L.of(context).privacyDocNoOutsideListening,
        L.of(context).privacyDocNoPayments,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return ScreenChrome(
      embedded: embedded,
      header: ScreenHeader(
        title: L.of(context).aboutDataPrivacy,
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
                    L.of(context).privacyDocStoredTitle,
                    style: texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    L.of(context).privacyDocStoredHint,
                    style: texts.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final item in _stored(context)) ...[
                    _DataRow(
                      icon: item.icon,
                      title: item.title,
                      detail: item.detail,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text(L.of(context).privacyDocNotStoredTitle, style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final line in _notStored(context)) ...[
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
                  Text(L.of(context).privacyDocHowToDeleteTitle, style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    L.of(context).privacyDocHowToDeleteText,
                    style: texts.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(L.of(context).privacyDocFullTitle, style: texts.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    L.of(context).privacyDocFullHint,
                    style: texts.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onOpenFullText ??
                        () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LegalDocumentScreen(
                                  title: L.of(context).aboutPrivacyPolicy,
                                  assetPath: Config.privacyPolicyAsset,
                                  url: Config.privacyPolicyUrl,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: Text(L.of(context).aboutPrivacyPolicy),
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