class AppConfig {
  const AppConfig({
    required this.appName,
    required this.appBaseUri,
    required this.apiBaseUri,
    required this.websocketUri,
    required this.environmentLabel,
    required this.useDemoData,
  });

  final String appName;
  final Uri appBaseUri;
  final Uri apiBaseUri;
  final Uri websocketUri;
  final String environmentLabel;
  final bool useDemoData;

  factory AppConfig.fromEnvironment() {
    const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Mynube');
    const appBaseUrl = String.fromEnvironment(
      'APP_BASE_URL',
      defaultValue: 'https://mynube.live',
    );
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.mynube.live/api/v1',
    );
    const websocketUrl = String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: 'wss://api.mynube.live/ws/progress',
    );
    const environmentLabel = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'production',
    );
    const useDemoData = bool.fromEnvironment(
      'USE_DEMO_DATA',
      defaultValue: false,
    );

    return AppConfig(
      appName: appName,
      appBaseUri: Uri.parse(appBaseUrl),
      apiBaseUri: _normalizeApiBase(Uri.parse(apiBaseUrl)),
      websocketUri: _normalizeWebsocket(Uri.parse(websocketUrl)),
      environmentLabel: environmentLabel,
      useDemoData: useDemoData,
    );
  }

  bool get isProduction => environmentLabel.toLowerCase() == 'production';

  static Uri _normalizeApiBase(Uri uri) {
    final baseSegments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    if (baseSegments.length < 2 ||
        baseSegments[baseSegments.length - 2] != 'api' ||
        baseSegments.last != 'v1') {
      baseSegments.addAll(const ['api', 'v1']);
    }

    return uri.replace(pathSegments: baseSegments);
  }

  static Uri _normalizeWebsocket(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    if (segments.isEmpty) {
      segments.addAll(const ['ws', 'progress']);
    }

    return uri.replace(pathSegments: segments);
  }
}
