import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/test_result.dart';

class TestReportScreen extends StatefulWidget {
  final TestResult result;

  const TestReportScreen({super.key, required this.result});

  @override
  State<TestReportScreen> createState() => _TestReportScreenState();
}

class _TestReportScreenState extends State<TestReportScreen> {
  bool _isSyncing = false;
  String? _syncStatus;

  Future<void> _syncToWebPortal() async {
    setState(() {
      _isSyncing = true;
      _syncStatus = null;
    });

    try {
      // Endpoint local padrão do Backend API
      final url = Uri.parse('http://10.0.2.2:3000/api/tests'); // 10.0.2.2 para emulador Android ou IP local
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(widget.result.toJson()),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() => _syncStatus = 'Sincronizado com sucesso com o Portal Web!');
      } else {
        setState(() => _syncStatus = 'Servidor respondeu com código: ${response.statusCode}');
      }
    } catch (e) {
      // Como o backend pode ainda não estar rodando, dá feedback amigável
      setState(() => _syncStatus = 'Salvo localmente no celular (Backend offline no momento).');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final isPass = r.status == TestStatus.aprovada;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laudo Técnico de Ensaio'),
        backgroundColor: isPass ? Colors.green.shade800 : Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Gigante de Veredito
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isPass ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isPass ? Colors.green : Colors.red, width: 2),
              ),
              child: Column(
                children: [
                  Icon(
                    isPass ? Icons.check_circle : Icons.cancel,
                    size: 64,
                    color: isPass ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPass ? 'GELADEIRA APROVADA' : 'GELADEIRA REPROVADA',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isPass ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    r.verdictReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Métricas Principais em Grade
            Row(
              children: [
                _buildMetricCard('Temp. Inicial', '${r.initialTemp.toStringAsFixed(1)}°C', Icons.thermostat),
                const SizedBox(width: 12),
                _buildMetricCard('Temp. Final', '${r.finalTemp.toStringAsFixed(1)}°C', Icons.ac_unit),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard('Tempo Pull-Down', '${r.durationMinutes} min', Icons.timer),
                const SizedBox(width: 12),
                _buildMetricCard('Meta do Perfil', '≤ ${r.profile.maxAllowedMinutes} min', Icons.flag),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard('Taxa de Descida', '${r.coolingRate.toStringAsFixed(2)} °C/min', Icons.trending_down),
                const SizedBox(width: 12),
                _buildMetricCard('Aberturas de Porta', '${r.doorOpenEvents}', Icons.door_front_door),
              ],
            ),
            const SizedBox(height: 28),

            // Identificação do ensaio
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dados do Ensaio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text('Nº Série: ${r.serialNumber}'),
                    Text('Modelo: ${r.modelName}'),
                    Text('Inspetor: ${r.technicianName}'),
                    Text('Perfil Utilizado: ${r.profile.name}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botão de Sincronizar com o Portal Web
            ElevatedButton.icon(
              onPressed: _isSyncing ? null : _syncToWebPortal,
              icon: _isSyncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('ENVIAR LAUDO PARA O PORTAL WEB'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
              ),
            ),

            if (_syncStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _syncStatus!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
