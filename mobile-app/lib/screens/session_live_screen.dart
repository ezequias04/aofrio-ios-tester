import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/test_session.dart';
import '../models/test_result.dart';
import '../services/local_report_store.dart';
import '../theme/app_theme.dart';
import 'test_report_screen.dart';

class SessionLiveScreen extends StatefulWidget {
  final TestSession session;
  final VoidCallback onSessionFinished;

  const SessionLiveScreen({
    super.key,
    required this.session,
    required this.onSessionFinished,
  });

  @override
  State<SessionLiveScreen> createState() => _SessionLiveScreenState();
}

class _SessionLiveScreenState extends State<SessionLiveScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Atualiza a UI a cada segundo para o relógio e curva
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Color _tempColor(double temp) {
    if (temp <= widget.session.profile.targetTemperature) {
      return AppColors.success;
    }
    if (temp <= widget.session.profile.maxTemperature) {
      return AppColors.ocean;
    }
    return AppColors.warning;
  }

  Future<void> _finishAndGenerateReport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Ensaio Pull-Down?'),
        content: Text(
          'Deseja concluir a qualificação do equipamento ${widget.session.equipmentSerial} e emitir o Laudo Técnico ISO 23953?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Continuar Testando')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Finalizar & Gerar Laudo')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = widget.session.finishTest();
    await LocalReportStore.save(result);
    widget.onSessionFinished();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TestReportScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final color = _tempColor(session.currentTemperature);
    final target = session.profile.targetTemperature;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.equipmentSerial),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ice,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  session.elapsedFormatted,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: AppColors.ocean,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banner do Equipamento e Sensor
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.kitchen, color: AppColors.ocean),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                session.equipmentModel,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _Badge(icon: Icons.sensors, label: 'Sensor: ${session.sensorDevice.name}'),
                            _Badge(icon: Icons.badge_outlined, label: 'Técnico: ${session.technicianName}'),
                            _Badge(icon: Icons.thermostat, label: 'Norma: ${session.profile.name} (Alvo: $target°C)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mostrador Principal de Temperatura
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: color.withValues(alpha: 0.35), width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(
                          session.currentTemperature.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 76,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '°C (Temperatura Atual)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.currentTemperature <= target
                              ? 'FAIXA ALVO ATINGIDA • ESTABILIZANDO'
                              : 'RESFRIANDO EM PULL-DOWN • META: $target°C',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cards de Status (Porta / Compressor / Sinal)
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Porta',
                          value: session.doorOpen ? 'Aberta' : 'Fechada',
                          icon: session.doorOpen ? Icons.meeting_room : Icons.door_front_door,
                          color: session.doorOpen ? AppColors.warning : AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'Compressor',
                          value: session.compressorOn ? 'Ativo' : 'Desligado',
                          icon: Icons.power,
                          color: session.compressorOn ? AppColors.ocean : AppColors.slate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'Sinal BLE',
                          value: '${session.sensorDevice.rssi} dBm',
                          icon: Icons.wifi,
                          color: AppColors.ocean,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Gráfico da Curva em Tempo Real
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Curva de Resfriamento em Tempo Real',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                '${session.readings.length} pontos',
                                style: const TextStyle(fontSize: 12, color: AppColors.slate),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Gráfico atualizado continuamente durante o ensaio pull-down.',
                            style: TextStyle(fontSize: 12, color: AppColors.slate),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 220,
                            child: _buildChart(session),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botão de Finalização
                  FilledButton.icon(
                    onPressed: _finishAndGenerateReport,
                    icon: const Icon(Icons.assignment_turned_in),
                    label: const Text('Concluir Ensaio & Emitir Laudo ISO 23953'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ocean,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

  Widget _buildChart(TestSession session) {
    if (session.readings.isEmpty) {
      return const Center(
        child: Text(
          'Aguardando primeiras amostras do sensor…',
          style: TextStyle(color: AppColors.slate),
        ),
      );
    }

    final spots = <FlSpot>[];
    final start = session.startTime;
    for (final r in session.readings) {
      final x = r.timestamp.difference(start).inSeconds / 60.0;
      spots.add(FlSpot(x, r.temperature));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.isEmpty ? 1 : (spots.last.x > 1 ? spots.last.x : 1),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.ocean,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.ocean.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.slate),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.slate, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
