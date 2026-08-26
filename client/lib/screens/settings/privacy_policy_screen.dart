import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
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

    return SettingsSectionScreen(
      title: L.of(context).aboutDataPrivacy,
      embedded: embedded,
      onBack: onBack,
      children: [
        SettingsGroup(
          title: L.of(context).privacyDocStoredTitle,
          footer: L.of(context).privacyDocStoredHint,
          children: [
            for (final item in _stored(context))
              SettingsInfo(
                icon: item.icon,
                title: item.title,
                subtitle: item.detail,
              ),
          ],
        ),

        SettingsGroup(
          title: L.of(context).privacyDocNotStoredTitle,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SettingsMetrics.rowPaddingH,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _notStored(context))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.remove_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm + 4),
                          Expanded(
                            child: Text(
                              line,
                              style: texts.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        SettingsGroup(
          title: L.of(context).privacyDocHowToDeleteTitle,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SettingsMetrics.rowPaddingH,
                vertical: AppSpacing.md,
              ),
              child: Text(
                L.of(context).privacyDocHowToDeleteText,
                style:
                    texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),

        SettingsGroup(
          title: L.of(context).privacyDocFullTitle,
          footer: L.of(context).privacyDocFullHint,
          children: [
            SettingsAction(
              icon: Icons.article_outlined,
              title: L.of(context).aboutPrivacyPolicy,
              chevron: true,
              onTap: onOpenFullText ??
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen(
                            title: L.of(context).aboutPrivacyPolicy,
                            assetPath: Config.privacyPolicyAsset,
                            url: Config.privacyPolicyUrl,
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ],
    );
  }
}