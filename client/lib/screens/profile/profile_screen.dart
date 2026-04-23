import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../utils/web_redirect.dart';
import 'package:url_launcher/url_launcher.dart';

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
            if (auth.isLoggedIn) ...[
              ElevatedButton(
                onPressed: () async {
                  final api = ApiService();

                  if (kIsWeb) {
                    final url = '${api.baseUrl}/auth/login?returnTo=${Uri.base.toString()}';
                    redirectTo(url);
                  } else {
                    final completer = Completer<Map<String, dynamic>?>();
                    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);

                    final url = Uri.parse('${api.baseUrl}/auth/login?returnTo=http://localhost:8080/callback');
                    await launchUrl(url, mode: LaunchMode.externalApplication);

                    server.listen((request) async {
                      final response = request.response;
                      response.headers.set('Content-Type', 'text/html');
                      response.write('<html><body><h2>Spotify подключён! Можно закрыть вкладку.</h2></body></html>');
                      await response.close();
                      await server.close();
                      completer.complete({'done': true});
                    });

                    final result = await completer.future.timeout(
                      const Duration(minutes: 2),
                      onTimeout: () {
                        server.close();
                        return null;
                      },
                    );

                    if (result != null) {
                      await auth.fetchMe();
                    }
                  }
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