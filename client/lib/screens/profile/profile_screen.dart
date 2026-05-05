import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
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
                      radius: 50,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                      backgroundImage: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                          ? Icon(Icons.person, size: 50, color: theme.colorScheme.primary)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.displayName ?? 'Пользователь',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?.email ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              
              // Информация о профиле
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Информация',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(theme, 'Имя', user?.displayName ?? 'Не указано'),
                      const Divider(height: 24),
                      _buildInfoRow(theme, 'Email', user?.email ?? 'Не указан'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Статус Spotify
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
                            user?.spotifyConnected == true 
                                ? Icons.check_circle 
                                : Icons.cancel,
                            color: user?.spotifyConnected == true 
                                ? Colors.green 
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            user?.spotifyConnected == true 
                                ? 'Spotify подключен' 
                                : 'Spotify не подключен',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user?.spotifyConnected == true
                            ? 'Ваш аккаунт уже авторизован'
                            : 'Подключите Spotify для доступа к плейлистам',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Кнопки Spotify
                      if (user?.spotifyConnected == true)
                        OutlinedButton.icon(
                          onPressed: () => _disconnectSpotify(context),
                          icon: const Icon(Icons.link_off),
                          label: const Text('Отключить Spotify'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => _connectSpotify(context),
                          icon: const Icon(Icons.link),
                          label: const Text('Подключить Spotify'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Кнопка выхода из аккаунта Google
              ElevatedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти из аккаунта'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Кнопка выхода из Spotify (если подключен)
              if (user?.spotifyConnected == true)
                OutlinedButton.icon(
                  onPressed: () => _disconnectSpotify(context),
                  icon: const Icon(Icons.music_off),
                  label: const Text('Выйти из Spotify'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

    void _connectSpotify(BuildContext context) {
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    final authUrl = '${api.baseUrl}/auth/login';
    
    // Открываем страницу авторизации Spotify
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Подключение Spotify'),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.music_note,
                  size: 64,
                  color: Color(0xFF1DB954),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Подключите Spotify\nдля доступа к плейлистам',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      // Используем url_launcher для открытия в браузере
                      final uri = Uri.parse(authUrl);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Авторизоваться в Spotify'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                // Обновляем данные пользователя
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
  }
}