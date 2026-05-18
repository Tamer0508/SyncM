import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'spotify_webview_screen.dart'
    if (dart.library.html) 'spotify_webview_stub.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayId; // ID пользователя, чей профиль показываем
  Map<String, dynamic>? _profileData;
  bool _loading = false;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки профиля: $e')),
        );
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

    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                    backgroundImage:
                        avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Icon(Icons.person, size: 50, color: theme.colorScheme.primary)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Информация
            if (isOwnProfile)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Информация',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      _buildInfoRow(theme, 'Имя', auth.user?.displayName ?? 'Не указано'),
                      const Divider(height: 24),
                      _buildInfoRow(theme, 'Email', auth.user?.email ?? 'Не указан'),
                    ],
                  ),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Информация',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      _buildInfoRow(theme, 'Имя', displayName),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Друзья
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Друзья',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _buildInfoRow(theme, 'Количество друзей', '$friendsCount'),
                    if (!isOwnProfile && mutualCount > 0)
                      _buildInfoRow(theme, 'Общие друзья', '$mutualCount'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Spotify – только для своего профиля
            if (isOwnProfile)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            auth.user?.spotifyConnected == true
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: auth.user?.spotifyConnected == true
                                ? AppTheme.spotifyGreen
                                : theme.iconTheme.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            auth.user?.spotifyConnected == true
                                ? 'Spotify подключен'
                                : 'Spotify не подключен',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        auth.user?.spotifyConnected == true
                            ? 'Ваш аккаунт уже авторизован'
                            : 'Подключите Spotify для доступа к плейлистам',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (auth.user?.spotifyConnected == true)
                        OutlinedButton.icon(
                          onPressed: () => _disconnectSpotify(context),
                          icon: const Icon(Icons.link_off),
                          label: const Text('Отключить Spotify'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => _connectSpotify(context),
                          icon: const Icon(Icons.link),
                          label: const Text('Подключить Spotify'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.spotifyGreen,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (isOwnProfile) const SizedBox(height: 20),

            // Выход – только для своего профиля
            if (isOwnProfile)
              ElevatedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти из аккаунта'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            if (isOwnProfile) const SizedBox(height: 12),
            if (isOwnProfile && auth.user?.spotifyConnected == true)
              OutlinedButton.icon(
                onPressed: () => _disconnectSpotify(context),
                icon: const Icon(Icons.music_off),
                label: const Text('Выйти из Spotify'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnProfile ? 'Профиль' : displayName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : content,
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _encodeState(Map<String, String> data) {
    return base64Url.encode(utf8.encode(jsonEncode(data)));
  }

  void _connectSpotify(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = auth.api;
    final userId = auth.user?.id ?? '';

    if (kIsWeb) {
      final webState = _encodeState({
        'returnTo': Uri.base.origin,
        'userId': userId,
      });
      final webUrl = '${api.baseUrl}/auth/login?state=${Uri.encodeComponent(webState)}';
      redirectToUrl(webUrl);
    } else {
      final state = _encodeState({'returnTo': 'myapp://callback', 'userId': userId});
      final authUrl = '${api.baseUrl}/auth/login?state=${Uri.encodeComponent(state)}';

      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => buildSpotifyWebView(authUrl)),
      );

      if (result != null) {
        final token = result['token'] as String?;
        final cookie = result['cookie'] as String?;
        if (token != null && token.isNotEmpty) {
          auth.setCookie(token);
        } else if (cookie != null && cookie.isNotEmpty) {
          auth.setCookie(cookie);
        }
        await auth.fetchMe();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Spotify успешно подключён!')),
          );
        }
      }
    }
  }

  void _disconnectSpotify(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить Spotify'),
        content: const Text('Вы уверены, что хотите отключить Spotify аккаунт?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final api = Provider.of<AuthProvider>(context, listen: false).api;
                await api.disconnectSpotify();
                final auth = Provider.of<AuthProvider>(context, listen: false);
                await auth.fetchMe();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Spotify отключен')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход из аккаунта'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта Google?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final auth = Provider.of<AuthProvider>(context, listen: false);
              auth.logout();
              Navigator.of(context).pushReplacementNamed('/');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}