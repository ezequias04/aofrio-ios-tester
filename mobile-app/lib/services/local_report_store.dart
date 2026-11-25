import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/test_result.dart';

abstract final class LocalReportStore {
  static const _storageKey = 'aofrio_local_reports_v1';

  static Future<void> save(TestResult result, {bool? synced}) async {
    final preferences = await SharedPreferences.getInstance();
    final reports = preferences.getStringList(_storageKey) ?? <String>[];
    final effectiveSynced = synced ?? result.synced;
    final payload = <String, dynamic>{
      ...result.copyWith(synced: effectiveSynced).toJson(),
      'savedAt': DateTime.now().toIso8601String(),
      'synced': effectiveSynced,
    };

    reports.removeWhere((item) {
      try {
        return jsonDecode(item)['testId'] == result.testId;
      } catch (_) {
        return true;
      }
    });
    // Sem limite automático: laudo só sai do aparelho quando o técnico apaga.
    // ponytail: lista em SharedPreferences; acima de ~500 laudos migrar para SQLite.
    reports.insert(0, jsonEncode(payload));
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
      } catch (e) {
        // Laudo corrompido não derruba a lista; fica registrado no log.
        debugPrint('Laudo ilegível ignorado: $e');
      }
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
