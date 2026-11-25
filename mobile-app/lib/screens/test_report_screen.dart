import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/diagnostic_finding.dart';
import '../models/test_result.dart';
import '../theme/app_theme.dart';
import '../widgets/thermal_chart.dart';

class TestReportScreen extends StatefulWidget {
  final TestResult result;
  const TestReportScreen({super.key, required this.result});

  @override
  State<TestReportScreen> createState() => _TestReportScreenState();
}

class _TestReportScreenState extends State<TestReportScreen> {
  Future<void> _deleteReport() async {
    final controller = BenchScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir laudo deste aparelho?'),
        content: Text(
          'Remover o registro local de ${widget.result.serialNumber}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.fault),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteReport(widget.result.testId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _copyOfficialReport() {
    final r = widget.result;
    final String statusStr = switch (r.status) {
      TestStatus.aprovada => 'APROVADA (CONFORME)',
      TestStatus.reprovada => 'REPROVADA (NAO CONFORME)',
      TestStatus.inconclusiva => 'INCONCLUSIVA (ENSAIO INTERROMPIDO)',
    };

    final causesText = r.probableCauses.isEmpty
        ? ''
        : '\nCAUSAS PROVAVEIS:\n${r.probableCauses.map((c) => '- $c').join('\n')}';

    final actionsText = r.recommendedActions.isEmpty
        ? ''
        : '\nPLANO DE ACAO / OFICINA:\n${r.recommendedActions.map((a) => '- $a').join('\n')}';

    final notesText = r.manualNotes.isEmpty
        ? ''
        : '\nANOTACOES EM CAMPO:\n${r.manualNotes.map((n) => '- $n').join('\n')}';

    final text = '''
LAUDO TECNICO E DIAGNOSTICO - ISO TEST
==========================================
Equipamento: ${r.serialNumber} (${r.modelName})
Tecnico: ${r.technicianName}
Norma: ${r.profile.name}
Origem dos dados: ${r.dataSource}${r.isSimulated ? ' [SIMULACAO]' : ''}
Data/Hora: ${r.startTime.toLocal().toString().split('.').first}
Status: $statusStr
Diagnostico: ${r.faultCategory.label}

METRICAS TERMICAS:
• Temperatura Inicial (T0): ${r.initialTemp.toStringAsFixed(1)}°C (${r.t0Validated ? 'Validado' : 'Pre-resfriado'})
• Temperatura Final: ${r.finalTemp.toStringAsFixed(1)}°C
• Setpoint Alvo: ${r.profile.targetTemperature}°C
• Duracao: ${r.durationMinutes} min (limite ${r.effectiveAllowedMinutes} min)
• Taxa Media de Resfriamento: ${r.coolingRate.toStringAsFixed(2)}°C/min

PARECER TECNICO:
${r.verdictReason}
$causesText
$actionsText
$notesText

ID Rastreabilidade: ${r.testId}
Ensaio de pull-down em campo com 1 sensor. Nao e ensaio normativo em camara climatica
(ISO 23953) e nao substitui certificacao do fabricante.
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Laudo completo copiado para WhatsApp ou Email.'),
        backgroundColor: AppColors.approved,
      ),
    );
  }

  /// Exporta as leituras de temperatura em CSV (data/hora ISO local e °C) para
  /// a área de transferência: dá para colar em planilha, e-mail ou WhatsApp.
  void _copyReadingsCsv() {
    final r = widget.result;
    final sb = StringBuffer('equipamento,data_hora,temperatura_c\n');
    for (final p in r.readings) {
      sb.writeln(
          '${r.serialNumber},${p.timestamp.toLocal().toIso8601String()},${p.temperature.toStringAsFixed(2)}');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${r.readings.length} leituras copiadas em CSV.'),
        backgroundColor: AppColors.approved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isApproved = result.status == TestStatus.aprovada;
    final isRejected = result.status == TestStatus.reprovada;

    final Color color = isApproved
        ? AppColors.approved
        : (isRejected ? AppColors.fault : AppColors.warning);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laudo de Diagnóstico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Copiar laudo',
            onPressed: _copyOfficialReport,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Excluir registro local',
            onPressed: _deleteReport,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _VerdictHeroCard(result: result, color: color),
                      const SizedBox(height: 14),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _ChartSection(result: result, color: color),
                                  const SizedBox(height: 14),
                                  _DiagnosisChecklistCard(result: result, color: color),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 2,
                              child: _AuditDetailsCard(result: result),
                            ),
                          ],
                        )
                      else ...[
                        _DiagnosisChecklistCard(result: result, color: color),
                        const SizedBox(height: 14),
                        _ChartSection(result: result, color: color),
                        const SizedBox(height: 14),
                        _AuditDetailsCard(result: result),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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
          child: Center(
            heightFactor: 1,
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
                      onPressed: _copyReadingsCsv,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('Exportar CSV'),
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

class _VerdictHeroCard extends StatelessWidget {
  final TestResult result;
  final Color color;

  const _VerdictHeroCard({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    final String statusTitle = switch (result.status) {
      TestStatus.aprovada => 'PULL-DOWN APROVADO',
      TestStatus.reprovada => 'REPROVADA • FALHA DETECTADA',
      TestStatus.inconclusiva => 'ENSAIO INCONCLUSIVO',
    };
    final IconData icon = switch (result.status) {
      TestStatus.aprovada => Icons.verified_rounded,
      TestStatus.reprovada => Icons.warning_amber_rounded,
      TestStatus.inconclusiva => Icons.hourglass_bottom_rounded,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.serialNumber,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                if (result.isSimulated)
                  Container(
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
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              result.verdictReason,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosisChecklistCard extends StatelessWidget {
  final TestResult result;
  final Color color;

  const _DiagnosisChecklistCard({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.faultCategory.label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (result.probableCauses.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Causas Prováveis',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              ...result.probableCauses.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      Expanded(
                        child: Text(c,
                            style: const TextStyle(
                                color: AppColors.slate, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (result.recommendedActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Ações Recomendadas em Oficina',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              ...result.recommendedActions.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_box_outlined,
                          size: 16, color: AppColors.indigo),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(a,
                            style: const TextStyle(
                                color: AppColors.ink, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  final TestResult result;
  final Color color;

  const _ChartSection({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Curva de Pull-Down (${result.readings.length} pts)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ThermalCurveChart(
              readings: result.readings,
              targetTemp: result.profile.targetTemperature,
              safetyMinTemp: result.profile.safetyMinTemperature,
              accentColor: color,
              height: 230,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricPill('Inicial (T0)', '${result.initialTemp.toStringAsFixed(1)}°C'),
                _MetricPill('Final', '${result.finalTemp.toStringAsFixed(1)}°C'),
                _MetricPill('Taxa Média', '${result.coolingRate.toStringAsFixed(2)}°C/min'),
                _MetricPill('Duração', '${result.durationMinutes} min'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  const _MetricPill(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label  ',
          style: const TextStyle(color: AppColors.slate, fontSize: 12),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditDetailsCard extends StatelessWidget {
  final TestResult result;
  const _AuditDetailsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rastreabilidade & Auditoria',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _DetailRow('Modelo', result.modelName),
            _DetailRow('Técnico', result.technicianName),
            _DetailRow('Perfil', result.profile.displayShort),
            _DetailRow('Setpoint', '${result.profile.targetTemperature}°C'),
            _DetailRow('Limite tempo', '${result.effectiveAllowedMinutes} min'),
            _DetailRow('Baseline T0',
                result.t0Validated ? 'Validado' : 'Pré-resfriado'),
            _DetailRow('Origem dados', result.dataSource),
            if (result.sensorName.isNotEmpty)
              _DetailRow('Sensor', result.sensorName),
            if (result.reportedSymptom.isNotEmpty)
              _DetailRow('Queixa', result.reportedSymptom),
            _DetailRow('ID do laudo', result.testId, last: result.manualNotes.isEmpty),
            if (result.manualNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Anotações de Campo',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              ...result.manualNotes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('• $n',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.slate)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const _DetailRow(this.label, this.value, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.slate, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
