import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/test_result.dart';
import '../services/credential_store.dart';
import '../services/local_report_store.dart';
import '../theme/app_theme.dart';

class TestReportScreen extends StatefulWidget {
  final TestResult result;
  const TestReportScreen({super.key, required this.result});

  @override
  State<TestReportScreen> createState() => _TestReportScreenState();
}

class _TestReportScreenState extends State<TestReportScreen> {
  bool _isSyncing = false;
  bool _synced = false;
  String? _syncMessage;

  Future<void> _syncToWebPortal() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = null;
    });

    final endpoints = [
      '${AppConfig.apiBaseUrl}/api/tests',
      'http://localhost:3000/api/tests',
      'http://10.0.2.2:3000/api/tests',
      'http://192.168.0.68:3000/api/tests',
    ];

    bool success = false;
    String? lastError;

    for (final url in endpoints) {
      try {
        final uri = Uri.parse(url);
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(widget.result.toJson()),
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          success = true;
          break;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (success) {
      await LocalReportStore.save(widget.result, synced: true);
      if (mounted) {
        setState(() {
          _synced = true;
          _syncMessage = 'Laudo sincronizado com o portal com sucesso!';
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _syncMessage = 'Salvo localmente neste aparelho. Conecte ao Wi-Fi/PC para sincronizar com o portal.';
        });
      }
    }

    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  void _copyOfficialReport() {
    final r = widget.result;
    final passed = r.status == TestStatus.aprovada;
    final statusStr = passed ? 'APROVADA (CONFORME)' : 'REPROVADA (NÃO CONFORME)';

    final text = '''
📋 LAUDO DE ENSAIO PULL-DOWN ISO 23953
------------------------------------------
Patrimônio/Série: ${r.serialNumber}
Modelo: ${r.modelName}
Técnico Responsável: ${r.technicianName}
Data/Hora: ${r.startTime.toLocal().toString().split('.').first}
Status: $statusStr

MÉTRICAS TÉRMICAS:
• Temperatura Inicial: ${r.initialTemp.toStringAsFixed(1)}°C
• Temperatura Final: ${r.finalTemp.toStringAsFixed(1)}°C
• Setpoint Alvo: ${r.profile.targetTemperature}°C
• Duração do Pull-Down: ${r.durationMinutes} minutos
• Tempo Limite Permitido: ${r.effectiveAllowedMinutes} minutos
• Taxa Média de Resfriamento: ${r.coolingRate.toStringAsFixed(2)}°C/min
• Aberturas de Porta Registradas: ${r.doorOpenEvents}

PARECER TÉCNICO:
${r.verdictReason}

ID de Rastreabilidade: ${r.testId}
Sistema AoFrio Refrigeration Testing System
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Laudo técnico copiado! Pronto para enviar no WhatsApp ou Email.'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final passed = result.status == TestStatus.aprovada;
    final color = passed ? AppColors.success : AppColors.danger;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laudo do ensaio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Copiar laudo para WhatsApp',
            onPressed: _copyOfficialReport,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _VerdictCard(result: result, color: color, passed: passed),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _ChartCard(result: result, color: color)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _DetailsCard(result: result)),
                    ])
                  else ...[
                    _ChartCard(result: result, color: color),
                    const SizedBox(height: 16),
                    _DetailsCard(result: result),
                  ],
                  if (_syncMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _synced ? AppColors.ice : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _syncMessage!,
                        style: TextStyle(
                          color: _synced ? AppColors.ocean : const Color(0xFFE65100),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          );
        }),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Center(
            heightFactor: 1, // sem isso a barra ocupa a tela inteira
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyOfficialReport,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copiar Laudo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing || _synced ? null : _syncToWebPortal,
                      icon: _isSyncing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_synced ? Icons.cloud_done : Icons.cloud_upload_outlined),
                      label: Text(_synced ? 'Sincronizado' : 'Sincronizar Laudo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final TestResult result;
  final Color color;
  final bool passed;

  const _VerdictCard({required this.result, required this.color, required this.passed});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(passed ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: color, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              passed ? 'QUALIFICAÇÃO APROVADA' : 'QUALIFICAÇÃO REPROVADA',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(height: 2),
            Text(result.serialNumber, style: Theme.of(context).textTheme.titleLarge),
          ])),
        ]),
        const SizedBox(height: 16),
        Text(result.verdictReason, style: const TextStyle(fontSize: 15, height: 1.45)),
      ]),
    ),
  );
}

class _ChartCard extends StatelessWidget {
  final TestResult result;
  final Color color;

  const _ChartCard({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    if (result.readings.isNotEmpty) {
      final start = result.readings.first.timestamp;
      for (final reading in result.readings) {
        spots.add(FlSpot(reading.timestamp.difference(start).inMinutes.toDouble(), reading.temperature));
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Curva de resfriamento', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Temperatura registrada ao longo do ensaio.'),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: LineChart(LineChartData(
              minX: spots.isEmpty ? 0 : spots.first.x,
              maxX: spots.isEmpty ? 1 : spots.last.x,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 5,
                getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.line, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, _) => Text('${value.toInt()}°', style: const TextStyle(fontSize: 11, color: AppColors.slate)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: spots.isEmpty ? 1 : (spots.last.x / 4).clamp(1, 60).toDouble(),
                    getTitlesWidget: (value, _) => Text('${value.toInt()}m', style: const TextStyle(fontSize: 11, color: AppColors.slate)),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: color,
                  barWidth: 4,
                  isCurved: true,
                  curveSmoothness: .22,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .08)),
                ),
              ],
            )),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _Metric(label: 'Inicial', value: '${result.initialTemp.toStringAsFixed(1)}°C'),
            _Metric(label: 'Final', value: '${result.finalTemp.toStringAsFixed(1)}°C'),
            _Metric(label: 'Taxa', value: '${result.coolingRate.toStringAsFixed(2)}°C/min'),
            _Metric(label: 'Duração', value: '${result.durationMinutes} min'),
          ]),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(color: AppColors.snow, borderRadius: BorderRadius.circular(12)),
    child: Text.rich(TextSpan(
      text: '$label  ',
      style: const TextStyle(color: AppColors.slate, fontSize: 12),
      children: [TextSpan(text: value, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900))],
    )),
  );
}

class _DetailsCard extends StatelessWidget {
  final TestResult result;
  const _DetailsCard({required this.result});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Dados do ensaio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        _Detail(label: 'Modelo', value: result.modelName),
        _Detail(label: 'Técnico', value: result.technicianName),
        _Detail(label: 'Perfil', value: result.profile.name.split(' (').first),
        _Detail(label: 'Setpoint', value: '${result.profile.targetTemperature}°C'),
        _Detail(label: 'Tempo permitido', value: '${result.effectiveAllowedMinutes} min'),
        _Detail(label: 'Aberturas de porta', value: '${result.doorOpenEvents}'),
        _Detail(label: 'ID do laudo', value: result.testId, last: true),
      ]),
    ),
  );
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  final bool last;
  const _Detail({required this.label, required this.value, this.last = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 116, child: Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 12))),
      Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 13))),
    ]),
  );
}
