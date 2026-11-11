import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/test_result.dart';

abstract final class LocalReportStore {
  static const _storageKey = 'aofrio_local_reports_v1';

  static Future<void> save(TestResult result, {bool synced = false}) async {
    final preferences = await SharedPreferences.getInstance();
    final reports = preferences.getStringList(_storageKey) ?? <String>[];
    final payload = <String, dynamic>{
      ...result.toJson(),
      'savedAt': DateTime.now().toIso8601String(),
      'synced': synced,
    };

    reports.removeWhere((item) {
      try {
        return jsonDecode(item)['testId'] == result.testId;
      } catch (_) {
        return true;
      }
    });
    reports.insert(0, jsonEncode(payload));
    if (reports.length > 100) reports.removeRange(100, reports.length);
    await preferences.setStringList(_storageKey, reports);
  }

  static Future<int> count() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_storageKey) ?? const <String>[]).length;
  }

  static Future<List<TestResult>> getAll() async {
    final preferences = await SharedPreferences.getInstance();
    final reports = preferences.getStringList(_storageKey) ?? const <String>[];
    final List<TestResult> list = [];
    for (final raw in reports) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        list.add(TestResult.fromJson(map));
      } catch (_) {}
    }
    return list;
  }

  static Future<void> delete(String testId) async {
    final preferences = await SharedPreferences.getInstance();
    final reports = preferences.getStringList(_storageKey) ?? <String>[];
    reports.removeWhere((item) {
      try {
        return jsonDecode(item)['testId'] == testId;
      } catch (_) {
        return false;
      }
    });
    await preferences.setStringList(_storageKey, reports);
  }
}
