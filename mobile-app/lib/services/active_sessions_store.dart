import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bench_session.dart';

/// Persiste sessões ativas da bancada, último técnico e preferência de simulador.
/// Garante que fechar o app ou ficar sem rede nunca apaga leituras em andamento.
abstract final class ActiveSessionsStore {
  static const _sessionsKey = 'iso_test_active_sessions_v2';
  static const _techKey = 'iso_test_last_technician';
  static const _demoKey = 'iso_test_demo_mode';

  static Future<List<BenchSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(BenchSession.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSessions(List<BenchSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_sessionsKey, encoded);
  }

  static Future<String> loadLastTechnician() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_techKey) ?? '';
  }

  static Future<void> saveLastTechnician(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_techKey, trimmed);
  }

  static Future<bool> loadDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_demoKey) ?? false;
  }

  static Future<void> saveDemoMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoKey, enabled);
  }
}
