import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/diagnostic_finding.dart';
import '../../models/test_result.dart';
import '../../theme/app_theme.dart';
import '../test_report_screen.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  TestStatus? _filterStatus;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncAll() async {
    final controller = BenchScope.of(context);
    final outcome = await controller.syncAllPendingReports();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        backgroundColor:
            outcome.failedCount == 0 ? AppColors.approved : AppColors.warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final all = controller.savedReports;

    final approvedCount =
        all.where((r) => r.status == TestStatus.aprovada).length;
    final rejectedCount =
        all.where((r) => r.status == TestStatus.reprovada).length;
    final rate = all.isEmpty ? 0.0 : (approvedCount / all.length) * 100.0;
    final unsynced = controller.unsyncedCount;

    final filtered = all.where((r) {
      if (_filterStatus != null && r.status != _filterStatus) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final matches = r.serialNumber.toLowerCase().contains(q) ||
            r.modelName.toLowerCase().contains(q) ||
            r.technicianName.toLowerCase().contains(q) ||
            r.faultCategory.label.toLowerCase().contains(q);
        if (!matches) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laudos e Diagnósticos'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(
              children: [
                _KpiTile(label: 'Total', value: '${all.length}', color: AppColors.ink),
                const SizedBox(width: 8),
                _KpiTile(label: 'Aprovados', value: '$approvedCount', color: AppColors.approved),
                const SizedBox(width: 8),
                _KpiTile(label: 'Reprovados', value: '$rejectedCount', color: AppColors.fault),
                const SizedBox(width: 8),
                _KpiTile(
                  label: 'Taxa',
                  value: '${rate.toStringAsFixed(0)}%',
                  color: AppColors.indigo,
                ),
              ],
            ),
            if (unsynced > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.indigoSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        color: AppColors.indigo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$unsynced laudo(s) salvo(s) aguardando sincronização.',
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: controller.isSyncingBatch ? null : _syncAll,
                      child: Text(controller.isSyncingBatch
                          ? 'Enviando...'
                          : 'Sincronizar'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Buscar série, modelo, técnico ou falha...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: const Text('Limpar'),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _filterStatus == null,
                    onSelected: (_) => setState(() => _filterStatus = null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Aprovados'),
                    selected: _filterStatus == TestStatus.aprovada,
                    onSelected: (_) =>
                        setState(() => _filterStatus = TestStatus.aprovada),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Reprovados'),
                    selected: _filterStatus == TestStatus.reprovada,
                    onSelected: (_) =>
                        setState(() => _filterStatus = TestStatus.reprovada),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Inconclusivos'),
                    selected: _filterStatus == TestStatus.inconclusiva,
                    onSelected: (_) =>
                        setState(() => _filterStatus = TestStatus.inconclusiva),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.assignment_outlined,
                        size: 46,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        all.isEmpty
                            ? 'Nenhum laudo emitido ainda'
                            : 'Nenhum laudo corresponde ao filtro',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Inicie um diagnóstico na aba Bancada ou baixe o histórico da memória flash de um sensor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.slate, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map(
                (result) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportListCard(
                    result: result,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TestReportScreen(result: result),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportListCard extends StatelessWidget {
  final TestResult result;
  final VoidCallback onTap;

  const _ReportListCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isApproved = result.status == TestStatus.aprovada;
    final isRejected = result.status == TestStatus.reprovada;

    final Color color = isApproved
        ? AppColors.approved
        : (isRejected ? AppColors.fault : AppColors.warning);
    final Color bg = isApproved
        ? AppColors.approvedBg
        : (isRejected ? AppColors.faultBg : AppColors.warningBg);
    final IconData icon = isApproved
        ? Icons.verified_rounded
        : (isRejected ? Icons.warning_amber_rounded : Icons.hourglass_bottom_rounded);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${result.serialNumber} • ${result.modelName}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (result.isSimulated) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.warningBg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'SIM',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.faultCategory.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${result.initialTemp.toStringAsFixed(1)}°C → ${result.finalTemp.toStringAsFixed(1)}°C • ${result.durationMinutes} min • ${result.technicianName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    result.synced
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    size: 16,
                    color: result.synced ? AppColors.approved : AppColors.muted,
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
