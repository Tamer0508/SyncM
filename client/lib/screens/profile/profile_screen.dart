import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/web_redirect.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Имя: ${auth.user?.displayName ?? ''}'),
            const SizedBox(height: 8),
            Text('Email: ${auth.user?.email ?? ''}'),
            const SizedBox(height: 16),
            if (auth.isLoggedIn && (auth.user?.spotifyConnected ?? false)) ...[
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('Spotify подключен'),
                subtitle: const Text('Ваш аккаунт уже авторизован'),
                trailing: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              ),
            ] else if (auth.isLoggedIn) ...[
              ElevatedButton(
                onPressed: () async {
                  final api = ApiService();
                  if (kIsWeb) {
                    final url = '${api.baseUrl}/auth/login?returnTo=${Uri.encodeComponent(Uri.base.toString())}';
                    redirectTo(url);
                    return;
                  }
                  final uri = Uri.parse('${api.baseUrl}/auth/login');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Connect to Spotify'),
              ),
            ] else ...[
              const Text('Войдите через Google, чтобы подключить Spotify'),
            ],
          ],
        ),
      ),
    );
  }
}