import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/bench_session.dart';
import '../models/diagnostic_finding.dart';
import '../theme/app_theme.dart';
import '../widgets/thermal_chart.dart';
import 'test_report_screen.dart';

class DiagnosticLiveScreen extends StatefulWidget {
  final String sessionId;

  const DiagnosticLiveScreen({super.key, required this.sessionId});

  @override
  State<DiagnosticLiveScreen> createState() => _DiagnosticLiveScreenState();
}

class _DiagnosticLiveScreenState extends State<DiagnosticLiveScreen> {
  Timer? _tickTimer;
  bool _finishing = false;
  bool _mergingFlash = false;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  String _formatClock(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _addEventDialog(BenchSession session) async {
    final controller = BenchScope.of(context);
    final noteCtrl = TextEditingController();
    bool isDoor = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Anotar Evento em Campo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isDoor,
                    onChanged: (v) {
                      setModalState(() {
                        isDoor = v ?? false;
                        if (isDoor && noteCtrl.text.trim().isEmpty) {
                          noteCtrl.text = 'Porta aberta durante o ensaio';
                        }
                      });
                    },
                    title: const Text(
                      'Abertura de porta',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Registra evento no cálculo de choque térmico',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observação do técnico',
                      hintText: 'Ex.: Trocado relé PTC, limpo condensador',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Registrar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && noteCtrl.text.trim().isNotEmpty) {
      await controller.addNote(
        session.id,
        noteCtrl.text.trim(),
        isDoorEvent: isDoor,
      );
    }
    noteCtrl.dispose();
  }

  Future<void> _pullFlashMemory(BenchSession session) async {
    final controller = BenchScope.of(context);
    setState(() => _mergingFlash = true);
    try {
      final added = await controller.mergeFlashHistoryIntoSession(session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? 'Sincronizado! $added leitura(s) histórica(s) recuperada(s) da memória flash do sensor.'
                : 'Leitura concluída. Nenhum ponto adicional novo encontrado na flash.',
          ),
          backgroundColor: AppColors.approved,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.fault,
        ),
      );
    } finally {
      if (mounted) setState(() => _mergingFlash = false);
    }
  }

  Future<void> _confirmDiscard(BenchSession session) async {
    final controller = BenchScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar ensaio ativo?'),
        content: Text(
          'Os dados temporários de ${session.serialNumber} serão apagados sem gerar laudo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.fault),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.discardSession(session.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _finishAndGenerateReport(BenchSession session) async {
    final controller = BenchScope.of(context);
    if (session.readings.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Aguarde pelo menos 2 leituras do sensor para encerrar e gerar o laudo.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _finishing = true);
    try {
      final result =
          await controller.finalizeSession(session.id, allowPartial: true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TestReportScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.fault,
        ),
      );
      setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final session = controller.sessionById(widget.sessionId);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ensaio')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Esta sessão foi encerrada.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Voltar para Bancada'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final snapshot = controller.evaluateSessionLive(session);
    final stale = !session.isSimulated && session.isSignalStale();
    final elapsed = session.elapsed();

    Color healthColor;
    switch (snapshot.health) {
      case LiveHealth.excelente:
        healthColor = AppColors.approvedBright;
      case LiveHealth.normal:
        healthColor = AppColors.cryoBright;
      case LiveHealth.atencao:
        healthColor = AppColors.amber;
      case LiveHealth.critico:
        healthColor = AppColors.fault;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.serialNumber),
        actions: [
          if (session.isSimulated)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'SIMULAÇÃO',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            // Deck de Telemetria Obsidian
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${session.modelName} • ${session.profile.displayShort}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: healthColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          snapshot.phase.label,
                          style: TextStyle(
                            color: healthColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        snapshot.currentTemp == null
                            ? '—'
                            : snapshot.currentTemp!.toStringAsFixed(1),
                        style: TextStyle(
                          color: stale ? AppColors.muted : Colors.white,
                          fontSize: 54,
                          height: 0.95,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          '°C',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatClock(elapsed),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            'Meta ${session.profile.targetTemperature.toStringAsFixed(1)}°C',
                            style: const TextStyle(
                              color: AppColors.approvedBright,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: snapshot.progressRatio,
                      minHeight: 7,
                      backgroundColor: AppColors.carbon,
                      valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _DeckMetric(
                        label: 'T0 Inicial',
                        value: snapshot.initialTemp == null
                            ? '—'
                            : '${snapshot.initialTemp!.toStringAsFixed(1)}°C',
                      ),
                      _DeckMetric(
                        label: 'Queda ΔT',
                        value: '${snapshot.deltaTemp.toStringAsFixed(1)}°C',
                      ),
                      _DeckMetric(
                        label: 'Taxa atual',
                        value:
                            '${snapshot.recentCoolingRate.toStringAsFixed(2)}°/m',
                      ),
                      _DeckMetric(
                        label: 'Previsão ETA',
                        value: snapshot.targetReached
                            ? 'Atingida'
                            : (snapshot.estimatedMinutesToTarget == null
                                ? '—'
                                : '~${snapshot.estimatedMinutesToTarget}m'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Painel de Diagnóstico Preliminar ao Vivo
            Card(
              color: snapshot.health == LiveHealth.critico
                  ? AppColors.faultBg
                  : AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          snapshot.health == LiveHealth.critico
                              ? Icons.warning_amber_rounded
                              : Icons.medical_services_outlined,
                          color: snapshot.health == LiveHealth.critico
                              ? AppColors.fault
                              : AppColors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            snapshot.headline,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snapshot.subtext,
                      style:
                          const TextStyle(color: AppColors.slate, fontSize: 13),
                    ),
                    if (snapshot.preliminaryFinding != null) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Text(
                        'Possíveis causas detectadas:',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: AppColors.fault,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...snapshot.preliminaryFinding!.probableCauses
                          .take(3)
                          .map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $c',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.ink),
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Gráfico da Curva ao Vivo
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Curva Térmica (${session.readings.length} leituras)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          session.dataSource,
                          style: const TextStyle(
                            color: AppColors.indigo,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ThermalCurveChart(
                      readings: session.readings,
                      targetTemp: session.profile.targetTemperature,
                      safetyMinTemp: session.profile.safetyMinTemperature,
                      accentColor: AppColors.cryo,
                      height: 220,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Ações de Campo (Anotar evento + Puxar Flash SCS)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addEventDialog(session),
                    icon: const Icon(Icons.edit_note_rounded, size: 19),
                    label: const Text('Anotar Evento'),
                  ),
                ),
                if (!session.isSimulated) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mergingFlash
                          ? null
                          : () => _pullFlashMemory(session),
                      icon: _mergingFlash
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.memory_rounded, size: 18),
                      label: Text(_mergingFlash
                          ? 'Lendo Flash...'
                          : 'Puxar Flash SCS'),
                    ),
                  ),
                ],
              ],
            ),

            if (session.manualNotes.isNotEmpty ||
                session.reportedSymptom.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registros Técnicos da Sessão',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: AppColors.ink,
                        ),
                      ),
                      if (session.reportedSymptom.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Queixa inicial: ${session.reportedSymptom}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.slate),
                        ),
                      ],
                      ...session.manualNotes.map(
                        (n) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '• ${n.timestamp.toLocal().toString().substring(11, 16)} — ${n.text}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _finishing ? null : () => _confirmDiscard(session),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.fault),
                child: const Text('Descartar'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _finishing
                      ? null
                      : () => _finishAndGenerateReport(session),
                  icon: _finishing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.assignment_turned_in_rounded),
                  label: Text(
                    _finishing ? 'Gerando...' : 'Encerrar e Gerar Laudo',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckMetric extends StatelessWidget {
  final String label;
  final String value;

  const _DeckMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
