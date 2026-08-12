import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../services/api_service.dart';
import '../../services/spotify_link_service.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/screen_chrome.dart';
import '../../widgets/tappable_avatar.dart';
import 'spotify_webview_screen.dart'
    if (dart.library.html) 'spotify_webview_stub.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({
    super.key,
    this.embedded = false,
    this.overrideArgs,
    this.onBack,
    this.onOpenSettings,
  });

  final VoidCallback? onOpenSettings;

  final Map<String, dynamic>? overrideArgs;

  /// Как вернуться из встроенного вида.
  final VoidCallback? onBack;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayId;
  Map<String, dynamic>? _profileData;
  bool _loading = false;
  // Локальный сервер авторизации переехал в spotify_link_service вместе с
  // самой логикой подключения. Закрывать его здесь было неверно: авторизация
  // в браузере могла ещё идти, а уход с экрана обрывал приём возврата.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _determineTargetUser();
  }

  void _determineTargetUser() {
    final args = widget.overrideArgs ??
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    String? targetId;
    if (args != null && args['friendId'] != null) {
      targetId = args['friendId'] as String;
    } else {
      targetId = auth.user?.id;
    }

    if (targetId != null && targetId != _displayId) {
      _displayId = targetId;
      _loadProfile(targetId);
    }
  }

  Future<void> _loadProfile(String userId) async {
    setState(() => _loading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final data = await api.getUserProfile(userId);
      if (!mounted) return;
      setState(() => _profileData = data);
    } catch (e) {
      if (mounted && !(e is ApiException && e.suppressUiNotification)) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get isOwnProfile {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return _displayId == auth.user?.id;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);

    final displayName = isOwnProfile
        ? (auth.user?.displayName ?? 'Пользователь')
        : (_profileData?['displayName'] ?? 'Друг');
    final avatarUrl = isOwnProfile
        ? auth.user?.avatarUrl
        : _profileData?['avatarUrl'] as String?;
    final email = isOwnProfile ? auth.user?.email : null;
    final friendsCount = _profileData?['friendsCount'] ?? 0;
    final mutualCount = _profileData?['mutualFriendsCount'] ?? 0;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _ProfileContent(
              key: ValueKey(_displayId),
              theme: theme,
              isOwnProfile: isOwnProfile,
              displayName: displayName,
              avatarUrl: avatarUrl,
              email: email,
              friendsCount: friendsCount,
              mutualCount: mutualCount,
              profileData: _profileData,
              onConnectSpotify: () => connectSpotify(context),
              onDisconnectSpotify: () => disconnectSpotify(context),
            ),
          );

    return ScreenChrome(
      embedded: widget.embedded,
      header: ScreenHeader(
        title: isOwnProfile ? 'Профиль' : displayName,
        onBack: widget.onBack ??
            (widget.embedded ? null : () => Navigator.of(context).pop()),
        actions: isOwnProfile
            ? [
                AppIconButton(
                  icon: Icons.settings_outlined,
                  onPressed: widget.onOpenSettings ??
                      () => Navigator.of(context).pushNamed('/settings'),
                  tooltip: 'Настройки',
                ),
              ]
            : const [],
      ),
      child: body,
    );
  }

}


class _ProfileContent extends StatelessWidget {
  final ThemeData theme;
  final bool isOwnProfile;
  final String displayName;
  final String? avatarUrl;
  final String? email;
  final int friendsCount;
  final int mutualCount;
  final Map<String, dynamic>? profileData;
  final VoidCallback onConnectSpotify;
  final VoidCallback onDisconnectSpotify;

  const _ProfileContent({
    // key нужен: место вызова передаёт ValueKey(_displayId), чтобы
    // AnimatedSwitcher распознавал смену профиля и проигрывал переход.
    super.key,
    required this.theme,
    required this.isOwnProfile,
    required this.displayName,
    required this.avatarUrl,
    required this.email,
    required this.friendsCount,
    required this.mutualCount,
    required this.profileData,
    required this.onConnectSpotify,
    required this.onDisconnectSpotify,
  });

  @override
  Widget build(BuildContext context) {
    // watch, а не listen: false — раньше при подключении или отключении
    // Spotify карточка не перерисовывалась до перехода на другой экран,
    // потому что провайдер не был подписан.
    final auth = context.watch<AuthProvider>();
    final spotifyConnected = auth.user?.spotifyConnected == true;
    final colors = context.colors;
    final texts = context.texts;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _ProfileHeader(
          displayName: displayName,
          avatarUrl: avatarUrl,
          email: isOwnProfile ? email : null,
          isOwnProfile: isOwnProfile,
          profileData: profileData,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Счётчики вынесены из списка «ключ — значение» в отдельные плитки:
        // число друзей — это то, на что смотрят в профиле в первую очередь,
        // а строкой в таблице оно теряется среди прочих полей.
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '$friendsCount',
                label: 'Друзей',
                icon: Icons.people_rounded,
              ),
            ),
            if (!isOwnProfile && mutualCount > 0) ...[
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: _StatTile(
                  value: '$mutualCount',
                  label: 'Общих',
                  icon: Icons.handshake_rounded,
                ),
              ),
            ],
          ],
        ),

        if (isOwnProfile) ...[
          const SizedBox(height: AppSpacing.lg),
          _StatusRow(
            connected: spotifyConnected,
            onConnect: onConnectSpotify,
            onDisconnect: onDisconnectSpotify,
          ),
        ],

        if (!isOwnProfile && email != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            email!,
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Шапка профиля: аватар, имя, статус.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.avatarUrl,
    required this.email,
    required this.isOwnProfile,
    required this.profileData,
  });

  final String displayName;
  final String? avatarUrl;
  final String? email;
  final bool isOwnProfile;
  final Map<String, dynamic>? profileData;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Column(
      children: [
        // Нажатие разворачивает аватар на весь экран с плавным переходом.
        // Кольцо вокруг отделяет фотографию от фона, если её края по цвету
        // совпадают с поверхностью.
        TappableAvatar(
          imageUrl: avatarUrl,
          radius: 52,
          showRing: true,
          title: displayName,
          heroTag: 'profile-avatar-$displayName',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: texts.headlineMedium,
        ),
        if (email != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            email!,
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        if (!isOwnProfile) ...[
          const SizedBox(height: AppSpacing.sm),
          _OnlineStatus(profileData: profileData),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: AppSpacing.sm + 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: texts.headlineSmall),
              Text(label, style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final spotify = context.roles.spotify;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: connected ? onDisconnect : onConnect,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: [
              Icon(
                connected ? Icons.check_circle_rounded : Icons.link_rounded,
                size: 20,
                color: connected ? spotify : colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Text(
                  connected ? 'Spotify подключён' : 'Подключить Spotify',
                  style: texts.bodyMedium,
                ),
              ),
              Text(
                connected ? 'Отключить' : '',
                style: texts.labelMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded, size: 20, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  const _OnlineStatus({required this.profileData});

  final Map<String, dynamic>? profileData;

  @override
  Widget build(BuildContext context) {
    final data = profileData;
    if (data == null || data['isOnlineHidden'] == true) return const SizedBox.shrink();

    final colors = context.colors;
    final texts = context.texts;
    final isOnline = data['isOnline'] == true;

    if (isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.brand.online),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('В сети', style: texts.bodyMedium?.copyWith(color: context.brand.online)),
        ],
      );
    }

    final lastSeenAtStr = data['lastSeenAt'] as String?;
    final lastSeenAt = lastSeenAtStr != null ? DateTime.tryParse(lastSeenAtStr)?.toLocal() : null;
    if (lastSeenAt == null) return const SizedBox.shrink();

    final diff = DateTime.now().difference(lastSeenAt);
    final text = diff.inMinutes < 1
        ? 'только что'
        : diff.inMinutes < 60
            ? '${diff.inMinutes} мин. назад'
            : diff.inHours < 24
                ? '${diff.inHours} ч. назад'
                : '${diff.inDays} д. назад';

    return Text(
      'Был(а) в сети $text',
      style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
    );
  }
}