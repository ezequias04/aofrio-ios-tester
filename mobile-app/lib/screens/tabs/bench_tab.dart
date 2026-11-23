import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/bench_session.dart';
import '../../models/diagnostic_finding.dart';
import '../../theme/app_theme.dart';
import '../../widgets/iso_logo.dart';
import '../../widgets/thermal_chart.dart';
import '../diagnostic_live_screen.dart';

class BenchTab extends StatefulWidget {
  final VoidCallback onStartNewDiagnostic;
  final VoidCallback onGoToSensors;

  const BenchTab({
    super.key,
    required this.onStartNewDiagnostic,
    required this.onGoToSensors,
  });

  @override
  State<BenchTab> createState() => _BenchTabState();
}

class _BenchTabState extends State<BenchTab> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h}h ${m}m';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final sessions = controller.activeSessions;
    final sensors = controller.discoveredSensors;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: AppColors.obsidian,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const IsoLogo(size: 44, showBorder: true),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ISO Test',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Text(
                                'Diagnóstico Frigorífico + Sensor Térmico',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _RadarStatusChip(
                          scanning: controller.scanning,
                          demoMode: controller.demoModeEnabled,
                          onTap: widget.onGoToSensors,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _HeaderStat(
                          label: 'Em ensaio',
                          value: '${sessions.length}',
                          color: AppColors.cryoBright,
                        ),
                        const SizedBox(width: 10),
                        _HeaderStat(
                          label: 'Sensores',
                          value: '${sensors.length}',
                          color: AppColors.indigoBright,
                        ),
                        const SizedBox(width: 10),
                        _HeaderStat(
                          label: 'Laudos',
                          value: '${controller.savedReports.length}',
                          color: AppColors.approvedBright,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (controller.bleError != null && !controller.demoModeEnabled)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _BleAlertCard(
                message: controller.bleError!,
                onRetry: () => controller.startRadar(restart: true),
              ),
            ),
          ),
        if (sessions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
              child: _EmptyBenchView(
                sensorCount: sensors.length,
                demoMode: controller.demoModeEnabled,
                onStart: widget.onStartNewDiagnostic,
                onViewSensors: widget.onGoToSensors,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            sliver: SliverList.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final session = sessions[index];
                final snapshot = controller.evaluateSessionLive(session);
                return _ActiveSessionCard(
                  session: session,
                  snapshot: snapshot,
                  elapsedText: _formatDuration(session.elapsed()),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            DiagnosticLiveScreen(sessionId: session.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RadarStatusChip extends StatelessWidget {
  final bool scanning;
  final bool demoMode;
  final VoidCallback onTap;

  const _RadarStatusChip({
    required this.scanning,
    required this.demoMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = demoMode
        ? AppColors.amber
        : (scanning ? AppColors.approvedBright : AppColors.muted);
    final String label =
        demoMode ? 'SIMULAÇÃO' : (scanning ? 'RADAR BLE' : 'PAUSADO');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.carbon,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.slateDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.carbon,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.slateDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.05,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BleAlertCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _BleAlertCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reconectar'),
          ),
        ],
      ),
    );
  }
}

class _EmptyBenchView extends StatelessWidget {
  final int sensorCount;
  final bool demoMode;
  final VoidCallback onStart;
  final VoidCallback onViewSensors;

  const _EmptyBenchView({
    required this.sensorCount,
    required this.demoMode,
    required this.onStart,
    required this.onViewSensors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const IsoLogo(size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Bancada Pronta para Diagnóstico',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sensorCount > 0
                      ? '$sensorCount sensor(es) Wellington/AoFrio transmitindo temperatura ao vivo. Vincule um equipamento manualmente para iniciar a curva e detectar falhas.'
                      : 'O app nunca se conecta automaticamente em sensores. Escolha um sensor, leia o QR Code da geladeira, audite T0 e acompanhe várias geladeiras ao mesmo tempo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate, fontSize: 13.5),
                ),
                if (demoMode) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Modo Simulação Ativo — 2 sensores virtuais disponíveis',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _StepRow(
                  num: '1',
                  title: 'Escolha o sensor manual',
                  sub: 'BLE ao vivo ou baixe o log da memória flash SCS.',
                ),
                const SizedBox(height: 10),
                _StepRow(
                  num: '2',
                  title: 'Vincule patrimônio e norma',
                  sub: 'Leia o QR Code e defina Coca-Cola, Sub-Zero ou Freezer.',
                ),
                const SizedBox(height: 10),
                _StepRow(
                  num: '3',
                  title: 'Diagnóstico + Causa Raiz',
                  sub: 'Detecta falha de compressor, gás, bloqueio ou corte térmico.',
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Vincular Equipamento e Iniciar'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onViewSensors,
                  icon: const Icon(Icons.sensors_rounded),
                  label: Text(
                    sensorCount > 0
                        ? 'Ver $sensorCount sensor(es) no Radar'
                        : 'Abrir Radar de Sensores',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String num;
  final String title;
  final String sub;

  const _StepRow({required this.num, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.indigoSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            num,
            style: const TextStyle(
              color: AppColors.indigo,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final BenchSession session;
  final LiveDiagnosticSnapshot snapshot;
  final String elapsedText;
  final VoidCallback onTap;

  const _ActiveSessionCard({
    required this.session,
    required this.snapshot,
    required this.elapsedText,
    required this.onTap,
  });

  Color _healthColor() {
    switch (snapshot.health) {
      case LiveHealth.excelente:
        return AppColors.approved;
      case LiveHealth.normal:
        return AppColors.cryo;
      case LiveHealth.atencao:
        return AppColors.warning;
      case LiveHealth.critico:
        return AppColors.fault;
    }
  }

  Color _healthBg() {
    switch (snapshot.health) {
      case LiveHealth.excelente:
        return AppColors.approvedBg;
      case LiveHealth.normal:
        return AppColors.cryoSoft;
      case LiveHealth.atencao:
        return AppColors.warningBg;
      case LiveHealth.critico:
        return AppColors.faultBg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _healthColor();
    final stale = !session.isSimulated && session.isSignalStale();
    final temp = session.latestTemp;
    final ageSecs = session.lastSeenAt == null
        ? null
        : DateTime.now().difference(session.lastSeenAt!).inSeconds;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                session.serialNumber,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            if (session.isSimulated) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'SIMULAÇÃO',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.modelName} • ${session.profile.displayShort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _healthBg(),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      snapshot.phase.label,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            temp == null ? '—' : temp.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 38,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              color: stale ? AppColors.muted : AppColors.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4, left: 2),
                            child: Text(
                              '°C',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.slate,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Meta ${session.profile.targetTemperature.toStringAsFixed(1)}°C • ${session.readings.length} pts',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ThermalSparkline(
                      readings: session.readings,
                      color: accent,
                      height: 48,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: snapshot.progressRatio,
                  minHeight: 6,
                  backgroundColor: AppColors.canvas,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      snapshot.health == LiveHealth.critico
                          ? Icons.warning_amber_rounded
                          : Icons.analytics_outlined,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        snapshot.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    elapsedText,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.speed_rounded, size: 14, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    '${snapshot.recentCoolingRate.toStringAsFixed(2)} °C/m',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  if (stale)
                    Text(
                      ageSecs == null ? 'Sem sinal' : 'Sem sinal há ${ageSecs}s',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Abrir sala',
                          style: TextStyle(
                            color: AppColors.indigo,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.indigo,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
