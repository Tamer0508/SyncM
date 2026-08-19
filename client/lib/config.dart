class Config {
  const Config._();

  static const String _defaultBaseUrl = 'https://syncm-production.up.railway.app';

  static const String baseUrl =
      String.fromEnvironment('SYNCM_BASE_URL', defaultValue: _defaultBaseUrl);

  static const Duration requestTimeout = Duration(seconds: 20);

  static const Duration uploadTimeout = Duration(seconds: 60);

  static const int pageSize = 20;

  static const String appVersion = '1.0.0';

  static const String privacyPolicyAsset = 'assets/legal/privacy_policy.md';

  static const String termsAsset = 'assets/legal/terms_of_use.md';

  static String get privacyPolicyUrl => '$baseUrl/legal/privacy';
  static String get termsUrl => '$baseUrl/legal/terms';

  static bool get isLocal =>
      baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1') || baseUrl.contains('10.0.2.2');
}