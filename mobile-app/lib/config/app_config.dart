abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'AOFRIO_API_URL',
    defaultValue: 'https://aofrio-refrigeration.codigo-divino-estudio.workers.dev',
  );

  static const apiToken = String.fromEnvironment('AOFRIO_API_TOKEN');

  static bool get canSync => apiToken.trim().isNotEmpty;
}
