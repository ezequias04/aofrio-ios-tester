import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/test_result.dart';
import 'credential_store.dart';
import 'local_report_store.dart';

class SyncOutcome {
  final bool success;
  final String message;

  const SyncOutcome({required this.success, required this.message});
}

class BatchSyncOutcome {
  final int syncedCount;
  final int failedCount;
  final String message;

  const BatchSyncOutcome({
    required this.syncedCount,
    required this.failedCount,
    required this.message,
  });
}

/// Serviço unificado de sincronização com o Cloudflare Worker (portal ISO Test).
abstract final class ReportSyncService {
  static Future<String> resolveToken() async {
    if (AppConfig.canSync) return AppConfig.apiToken.trim();
    final local = await CredentialStore.readApiToken();
    return (local ?? '').trim();
  }

  static Future<bool> hasToken() async => (await resolveToken()).isNotEmpty;

  static Future<SyncOutcome> syncReport(TestResult result) async {
    final token = await resolveToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/tests');

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(result.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await LocalReportStore.save(result, synced: true);
        return const SyncOutcome(
          success: true,
          message: 'Laudo enviado para o portal com sucesso.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const SyncOutcome(
          success: false,
          message:
              'Token de autenticação ausente ou inválido. Configure a chave na aba Normas.',
        );
      }

      return SyncOutcome(
        success: false,
        message: 'Portal respondeu HTTP ${response.statusCode}. Mantido salvo offline.',
      );
    } catch (_) {
      return const SyncOutcome(
        success: false,
        message: 'Sem conexão com o portal no momento. Laudo seguro localmente.',
      );
    }
  }

  static Future<BatchSyncOutcome> syncAllPending() async {
    final pending = await LocalReportStore.getUnsynced();
    if (pending.isEmpty) {
      return const BatchSyncOutcome(
        syncedCount: 0,
        failedCount: 0,
        message: 'Todos os laudos já estão sincronizados.',
      );
    }

    int ok = 0;
    int fail = 0;
    for (final r in pending) {
      final res = await syncReport(r);
      if (res.success) {
        ok++;
      } else {
        fail++;
      }
    }

    if (ok > 0 && fail == 0) {
      return BatchSyncOutcome(
        syncedCount: ok,
        failedCount: 0,
        message: '$ok laudo(s) sincronizado(s) com o portal.',
      );
    }
    return BatchSyncOutcome(
      syncedCount: ok,
      failedCount: fail,
      message: ok > 0
          ? '$ok sincronizado(s), $fail pendente(s) por falta de rede/token.'
          : 'Não foi possível enviar os $fail laudo(s) agora. Verifique rede ou token.',
    );
  }
}
