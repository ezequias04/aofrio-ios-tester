import 'package:shared_preferences/shared_preferences.dart';

abstract final class CredentialStore {
  static const _apiTokenKey = 'aofrio_portal_api_token';

  static Future<String?> readApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiTokenKey);
  }

  static Future<void> saveApiToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiTokenKey, token.trim());
  }

  static Future<void> clearApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiTokenKey);
  }
}
