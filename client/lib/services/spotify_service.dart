import 'package:url_launcher/url_launcher.dart';

class SpotifyService {
  final String baseUrl;

  SpotifyService({String? baseUrl}) : baseUrl = baseUrl ?? 'http://10.0.2.2:3000';

  /// Возвращает URL для начала OAuth через сервер
  Uri getAuthUri() => Uri.parse('$baseUrl/auth/login');

  Future<void> launchAuth() async {
    final uri = getAuthUri();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $uri';
    }
  }
}
