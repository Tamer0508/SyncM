import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/error_utils.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/tappable_avatar.dart';
import 'spotify_webview_screen.dart'
    if (dart.library.html) 'spotify_webview_stub.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayId;
  Map<String, dynamic>? _profileData;
  bool _loading = false;
  HttpServer? _oauthServer;

  @override
  void dispose() {
    _oauthServer?.close(force: true);
    _oauthServer = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _determineTargetUser();
  }

  void _determineTargetUser() {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
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
    final isMobile = MediaQuery.of(context).size.width < 900;

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
              onConnectSpotify: () => _connectSpotify(context),
              onDisconnectSpotify: () => _disconnectSpotify(context),
              onLogout: () => _logout(context),
            ),
          );

    if (widget.embedded && isMobile && isOwnProfile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Профиль'),
          actions: [
            AppIconButton(
              icon: Icons.dark_mode,
              onPressed: () => Provider.of<ThemeProvider>(context, listen: false).toggleTheme(),
              tooltip: 'Тема',
            ),
            AppIconButton(
              icon: Icons.settings,
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
              tooltip: 'Настройки',
            ),
          ],
        ),
        body: body,
      );
    }

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnProfile ? 'Профиль' : displayName),
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }


  void _connectSpotify(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = auth.api;

    if (kIsWeb) {
      final state =
          await api.createSpotifyLinkIntent(returnTo: Uri.base.origin);
      final webUrl = '${api.baseUrl}/auth/login?state=$state';
      redirectToUrl(webUrl);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      HttpServer? server;
      try {
        if (_oauthServer != null) {
          try { await _oauthServer!.close(force: true); } catch (_) {}
          _oauthServer = null;
        }

        final completer = Completer<Map<String, dynamic>?>();
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4, 8282, shared: true,
        );
        _oauthServer = server;

        final state = await api.createSpotifyLinkIntent(
            returnTo: 'http://localhost:8282/callback');
        final authUrl = Uri.parse('${api.baseUrl}/auth/login?state=$state');
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        server.listen((request) async {
          final uri = request.requestedUri;
          final response = request.response;
          response.headers.set('Content-Type', 'text/html; charset=utf-8');
          response.write('<html><body><h2>Spotify connected! You can close this tab.</h2></body></html>');
          await response.close();
          await server!.close(force: true);
          _oauthServer = null;
          if (!completer.isCompleted) {
            completer.complete({
              'token': uri.queryParameters['token'],
              'cookie': uri.queryParameters['cookie'],
            });
          }
        });
        final result = await completer.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () async {
            try { await server?.close(force: true); } catch (_) {}
            _oauthServer = null;
            return null;
          },
        );
        if (result != null) {
          final token = result['token'] as String?;
          final cookie = result['cookie'] as String?;
          if (token != null && token.isNotEmpty) {
            auth.setCookie(token);
          } else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
          await auth.fetchMe();
          if (context.mounted) {
            showAppNotification(context, message: 'Spotify успешно подключён!', type: NotificationType.success);
          }
        }
      } catch (e) {
        // Гарантированно освобождаем порт при любой ошибке.
        try { await server?.close(force: true); } catch (_) {}
        _oauthServer = null;
        final msg = e.toString().contains('bind') || e.toString().contains('port')
            ? 'Не удалось начать подключение: предыдущая попытка ещё не завершилась. Подождите несколько секунд и попробуйте снова.'
            : 'Ошибка подключения: $e';
        if (context.mounted) showAppNotification(context, message: msg, type: NotificationType.error);
      }
      return;
    }

    // Android/iOS
    final state =
        await api.createSpotifyLinkIntent(returnTo: 'myapp://callback');
    final authUrl = '${api.baseUrl}/auth/login?state=$state';
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => buildSpotifyWebView(authUrl)),
    );
    if (result != null) {
      final token = result['token'] as String?;
      final cookie = result['cookie'] as String?;
      if (token != null && token.isNotEmpty) {
        auth.setCookie(token);
      } else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
      await auth.fetchMe();
      if (context.mounted) {
        showAppNotification(context, message: 'Spotify успешно подключён!', type: NotificationType.success);
      }
    }
  }

  void _disconnectSpotify(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.link_off, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Text('Отключить Spotify', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text('Вы уверены, что хотите отключить Spotify аккаунт?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final api = Provider.of<AuthProvider>(context, listen: false).api;
                await api.disconnectSpotify();
                final auth = Provider.of<AuthProvider>(context, listen: false);
                await auth.fetchMe();
                if (context.mounted) {
                  showAppNotification(context, message: 'Spotify отключен', type: NotificationType.success);
                }
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.logout, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Text('Выход из аккаунта', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final auth = Provider.of<AuthProvider>(context, listen: false);
              auth.logout();
              showAppNotification(context, message: 'Вы вышли из аккаунта', type: NotificationType.success);
              Navigator.of(context).pushReplacementNamed('/');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
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
  final VoidCallback onLogout;

  const _ProfileContent({
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
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
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
          _SpotifyCard(
            connected: spotifyConnected,
            onConnect: onConnectSpotify,
            onDisconnect: onDisconnectSpotify,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Выйти из аккаунта'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
            ),
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

class _SpotifyCard extends StatelessWidget {
  const _SpotifyCard({
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
    final spotify = context.brand.spotify;

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
                  color: spotify.withValues(alpha: 0.15),
                  borderRadius: AppRadius.small,
                ),
                child: Icon(Icons.music_note_rounded, color: spotify),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Spotify', style: texts.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      connected ? 'Аккаунт подключён' : 'Не подключён',
                      style: texts.bodySmall?.copyWith(
                        color: connected ? spotify : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            connected
                ? 'Плейлисты и воспроизведение доступны.'
                : 'Подключите Spotify, чтобы слушать музыку вместе с друзьями.',
            style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          if (connected)
            OutlinedButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Отключить'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
              ),
            )
          else
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Подключить Spotify'),
              style: FilledButton.styleFrom(
                backgroundColor: spotify,
                // Тёмный текст на зелёном Spotify: белый на нём не проходит
                // по контрасту и читается хуже.
                foregroundColor: const Color(0xFF07240F),
              ),
            ),
        ],
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