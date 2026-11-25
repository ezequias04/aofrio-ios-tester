import 'package:flutter/material.dart';
import '../engine/diagnostic_engine.dart';
import '../main.dart';
import '../models/test_profile.dart';
import '../services/wellington_ble_service.dart';
import '../state/bench_controller.dart';
import '../widgets/identity_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/thermal_chart.dart';
import 'asset_scanner_screen.dart';
import 'test_report_screen.dart';

/// Tela de leitura da memória flash do sensor (protocolo SCS: páginas de
/// 1024 B, cmd 5/1/3 + LZSS + CRC16) com geração de laudo. Para o técnico a
/// tela mostra só etapas em texto simples e o botão Cancelar.
class FlashLogScreen extends StatefulWidget {
  final String sensorId;
  final String sensorName;

  const FlashLogScreen({
    super.key,
    required this.sensorId,
    required this.sensorName,
  });

  @override
  State<FlashLogScreen> createState() => _FlashLogScreenState();
}

class _FlashLogScreenState extends State<FlashLogScreen> {
  bool _loading = true;
  String? _error;
  FlashDownloadResult? _download;
  BenchController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
  }

  @override
  void dispose() {
    // Ao sair da tela, a busca de sensores volta (ela fica parada enquanto a
    // memória flash é lida ou depois de uma falha).
    final controller = _controller;
    if (controller != null) Future.microtask(controller.resumeRadar);
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final controller = BenchScope.of(context);
    _controller = controller;
    try {
      final res = await controller.downloadFlashForSensor(widget.sensorId);
      if (mounted) {
        setState(() {
          _download = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _generateReportFromFlash() async {
    final download = _download;
    final problem = download == null
        ? 'Nenhum dado baixado do sensor.'
        : DiagnosticEngine.insufficientPartialData(download.readings);
    if (download == null || problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problem ?? 'Nenhum dado baixado do sensor.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final controller = BenchScope.of(context);
    final serialCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final symptomCtrl = TextEditingController();
    TestProfile profile = TestProfile.defaultProfiles.first;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  MediaQuery.of(context).viewInsets.bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Vincular Equipamento ao Histórico',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serialCtrl,
                        decoration: InputDecoration(
                          labelText: 'Patrimônio / Série',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            onPressed: () async {
                              final code = await Navigator.of(context)
                                  .push<String>(MaterialPageRoute(
                                      builder: (_) =>
                                          const AssetScannerScreen()));
                              if (code != null) {
                                setModalState(() => serialCtrl.text = code);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: modelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Modelo do refrigerador',
                        ),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge_outlined,
                            color: AppColors.indigo),
                        title: const Text('Técnico responsável',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13.5)),
                        subtitle: Text(controller.hasIdentity
                            ? controller.technicianLabel
                            : 'Não identificado'),
                        trailing: TextButton(
                          onPressed: () async {
                            await showIdentityDialog(context, controller);
                            setModalState(() {});
                          },
                          child: Text(controller.hasIdentity ? 'Trocar' : 'Informar'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<TestProfile>(
                        initialValue: profile,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Perfil de teste'),
                        items: TestProfile.defaultProfiles
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.displayShort),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => profile = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: symptomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Queixa relatada (opcional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                Navigator.of(modalContext).pop(false),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                if (serialCtrl.text.trim().isEmpty ||
                                    modelCtrl.text.trim().isEmpty ||
                                    !controller.hasIdentity) {
                                  return;
                                }
                                Navigator.of(modalContext).pop(true);
                              },
                              child: const Text('Gerar laudo'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    final signed = confirmed == true &&
        mounted &&
        await confirmTechnicianPin(context, controller);
    if (signed && mounted) {
      final result = await controller.createReportFromFlash(
        sensorId: widget.sensorId,
        sensorName: widget.sensorName,
        serialNumber: serialCtrl.text.trim(),
        modelName: modelCtrl.text.trim(),
        technicianName: controller.technicianLabel,
        profile: profile,
        readings: download.readings,
        reportedSymptom: symptomCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TestReportScreen(result: result)),
      );
    }

    serialCtrl.dispose();
    modelCtrl.dispose();
    symptomCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final download = _download;

    return Scaffold(
      appBar: AppBar(
        title: Text('Memória Flash • ${widget.sensorName}'),
        actions: [
          IconButton(
            tooltip: 'Ler novamente',
            onPressed: _loading ? null : _startDownload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Lendo a memória de ${widget.sensorName}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<String>(
                        valueListenable: BenchScope.of(context).flashStage,
                        builder: (context, stage, _) => Text(
                          stage.isEmpty ? 'Preparando...' : stage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.slate, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mantenha o celular perto do sensor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.slate, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await BenchScope.of(context).cancelFlashDownload();
                          if (mounted) Navigator.of(this.context).pop();
                        },
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancelar leitura'),
                      ),
                    ],
                  ),
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 42, color: AppColors.fault),
                              const SizedBox(height: 12),
                              const Text(
                                'Falha ao ler memória do sensor',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.slate, fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _startDownload,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      if (download != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Resumo do Datalogger Interno',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _StatPill(
                                        'Leituras: ${download.readings.length}'),
                                    _StatPill(
                                        'Blocos: ${download.blockCount}'),
                                    _StatPill(
                                        'Protocolo: v${download.protocolVersion}'),
                                    _StatPill(download.usedFastMode
                                        ? 'Modo Rápido BULK'
                                        : 'Modo Normal TX'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Curva Gravada na Memória Flash',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                ThermalCurveChart(
                                  readings: download.readings,
                                  targetTemp: 3.0,
                                  accentColor: AppColors.indigo,
                                  height: 220,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          title: const Text(
                            'Log técnico do protocolo SCS',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          backgroundColor: AppColors.surface,
                          collapsedBackgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.line),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.line),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: SelectableText(
                                download.diagnosticLines.join('\n'),
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
      ),
      bottomNavigationBar: download != null && download.readings.length >= 2
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: ElevatedButton.icon(
                  onPressed: _generateReportFromFlash,
                  icon: const Icon(Icons.assignment_turned_in_rounded),
                  label: const Text('Gerar Laudo deste Histórico'),
                ),
              ),
            )
          : null,
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  const _StatPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
