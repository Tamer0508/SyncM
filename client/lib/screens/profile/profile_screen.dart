import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/notifications.dart';
import '../../widgets/app_icon_button.dart';
import 'spotify_webview_screen.dart'
    if (dart.library.html) 'spotify_webview_stub.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayId;
  Map<String, dynamic>? _profileData;
  bool _loading = false;
  // Loopback-сервер Spotify OAuth (Windows). Держим ссылку, чтобы закрыть его
  // при уходе с экрана и не оставлять занятым порт 8282.
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
        showAppNotification(context, message: 'Ошибка загрузки профиля: $e', type: NotificationType.error);
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

  // ---------- Spotify connect / disconnect logic (unchanged) ----------

  String _encodeState(Map<String, String> data) => base64Url.encode(utf8.encode(jsonEncode(data)));

  void _connectSpotify(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = auth.api;
    final userId = auth.user?.id ?? '';

    if (kIsWeb) {
      final webState = _encodeState({'returnTo': Uri.base.origin, 'userId': userId});
      final webUrl = '${api.baseUrl}/auth/login?state=${Uri.encodeComponent(webState)}';
      redirectToUrl(webUrl);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      HttpServer? server;
      try {
        // Если предыдущая попытка логина не закрыла свой сервер (закрыли окно
        // браузера, не дойдя до callback) — порт 8282 остаётся занят, и новый
        // bind падает. Сначала закрываем прошлый сервер, если он ещё висит.
        if (_oauthServer != null) {
          try { await _oauthServer!.close(force: true); } catch (_) {}
          _oauthServer = null;
        }

        final completer = Completer<Map<String, dynamic>?>();
        // shared:true — как просит текст ошибки OS: разрешает повторный bind
        // на тот же (address, port), если прошлый сокет ещё не полностью освободился.
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4, 8282, shared: true,
        );
        _oauthServer = server;

        final state = _encodeState({'returnTo': 'http://localhost:8282/callback', 'userId': userId});
        final authUrl = Uri.parse('${api.baseUrl}/auth/login?state=${Uri.encodeComponent(state)}');
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        server.listen((request) async {
          final uri = request.requestedUri;
          final response = request.response;
          response.headers.set('Content-Type', 'text/html; charset=utf-8');
          response.write('<html><body><h2>Spotify connected! You can close this tab.</h2></body></html>');
          await response.close();
          // force:true — закрываем сразу, не дожидаясь keep-alive соединений,
          // иначе порт освобождается с задержкой и следующий логин падает.
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
          if (token != null && token.isNotEmpty) auth.setCookie(token);
          else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
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
    final state = _encodeState({'returnTo': 'myapp://callback', 'userId': userId});
    final authUrl = '${api.baseUrl}/auth/login?state=${Uri.encodeComponent(state)}';
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => buildSpotifyWebView(authUrl)),
    );
    if (result != null) {
      final token = result['token'] as String?;
      final cookie = result['cookie'] as String?;
      if (token != null && token.isNotEmpty) auth.setCookie(token);
      else if (cookie != null && cookie.isNotEmpty) auth.setCookie(cookie);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                if (context.mounted) showAppNotification(context, message: 'Ошибка: $e', type: NotificationType.error);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

// ---------- Контент профиля ----------

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
    Key? key,
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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final spotifyConnected = auth.user?.spotifyConnected == true;
    final emailValue = email ?? 'Не указан'; // гарантированный String

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // Аватар и имя
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: avatarUrl == null || avatarUrl!.isEmpty
                      ? Icon(Icons.person, size: 55, color: theme.colorScheme.primary)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(displayName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (email != null) ...[
                  const SizedBox(height: 6),
                  Text(email!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
                ],
                if (!isOwnProfile) _OnlineStatus(profileData: profileData, theme: theme),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Информация
          _SectionCard(
            theme: theme,
            title: 'Информация',
            children: [
              _InfoRow(theme: theme, label: 'Имя', value: isOwnProfile ? auth.user?.displayName ?? 'Не указано' : displayName),
              if (isOwnProfile) ...[
                const SizedBox(height: 16),
                _InfoRow(theme: theme, label: 'Email', value: emailValue),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Друзья
          _SectionCard(
            theme: theme,
            title: 'Друзья',
            children: [
              _InfoRow(theme: theme, label: 'Количество друзей', value: '$friendsCount'),
              if (!isOwnProfile && mutualCount > 0) ...[
                const SizedBox(height: 16),
                _InfoRow(theme: theme, label: 'Общие друзья', value: '$mutualCount'),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Spotify
          if (isOwnProfile)
            _SectionCard(
              theme: theme,
              title: 'Spotify',
              children: [
                Row(
                  children: [
                    Icon(spotifyConnected ? Icons.check_circle : Icons.cancel,
                        color: spotifyConnected ? AppTheme.spotifyGreen : theme.iconTheme.color),
                    const SizedBox(width: 8),
                    Text(spotifyConnected ? 'Подключен' : 'Не подключен',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spotifyConnected ? 'Ваш аккаунт авторизован' : 'Подключите Spotify для доступа к плейлистам',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                ),
                const SizedBox(height: 16),
                if (spotifyConnected)
                  OutlinedButton.icon(
                    onPressed: onDisconnectSpotify,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Отключить Spotify'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: onConnectSpotify,
                    icon: const Icon(Icons.link),
                    label: const Text('Подключить Spotify'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.spotifyGreen,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),

          // Кнопка выхода
          if (isOwnProfile)
            ElevatedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Выйти из аккаунта'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Переиспользуемые виджеты ----------

class _SectionCard extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.theme, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final String value;
  const _InfoRow({required this.theme, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  final Map<String, dynamic>? profileData;
  final ThemeData theme;
  const _OnlineStatus({required this.profileData, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (profileData == null || profileData!['isOnlineHidden'] == true) return const SizedBox.shrink();
    final isOnline = profileData!['isOnline'] == true;
    final lastSeenAtStr = profileData!['lastSeenAt'] as String?;
    final lastSeenAt = lastSeenAtStr != null ? DateTime.tryParse(lastSeenAtStr) : null;

    if (isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
          const SizedBox(width: 6),
          Text('В сети', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
        ],
      );
    } else if (lastSeenAt != null) {
      final diff = DateTime.now().difference(lastSeenAt);
      final text = diff.inMinutes < 1 ? 'только что'
          : diff.inMinutes < 60 ? '${diff.inMinutes} мин. назад'
          : diff.inHours < 24 ? '${diff.inHours} ч. назад'
          : '${diff.inDays} д. назад';
      return Text('Был(а) в сети $text', style: theme.textTheme.bodySmall);
    }
    return const SizedBox.shrink();
  }
}