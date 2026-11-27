import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/test_profile.dart';
import '../services/wellington_ble_service.dart';
import '../state/bench_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/identity_dialog.dart';
import 'asset_scanner_screen.dart';
import 'diagnostic_live_screen.dart';

/// Fluxo obrigatório em 3 passos antes de iniciar o cronômetro oficial (T0):
/// 1. Seleção manual do sensor (nunca conecta automaticamente)
/// 2. Vinculação do equipamento (QR Code / Patrimônio, Modelo e Norma)
/// 3. Técnico, sintoma relatado e Auditoria de T0 antes de liberar o início
class CommissioningWizardScreen extends StatefulWidget {
  final String? preselectedSensorId;

  const CommissioningWizardScreen({super.key, this.preselectedSensorId});

  @override
  State<CommissioningWizardScreen> createState() =>
      _CommissioningWizardScreenState();
}

class _CommissioningWizardScreenState extends State<CommissioningWizardScreen> {
  int _step = 0;
  String? _selectedSensorId;

  final _formKey = GlobalKey<FormState>();
  final _serialCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _symptomCtrl = TextEditingController();

  TestProfile _selectedProfile = TestProfile.defaultProfiles.first;
  bool _starting = false;

  static const _commonSymptoms = [
    'Não gela / temperatura alta',
    'Congelando bebidas',
    'Desarma / não parte compressor',
    'Suor ou acúmulo de gelo',
    'Revisão pós-manutenção',
  ];

  @override
  void initState() {
    super.initState();
    _selectedSensorId = widget.preselectedSensorId;
    if (_selectedSensorId != null) {
      _step = 1;
    }
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _modelCtrl.dispose();
    _symptomCtrl.dispose();
    super.dispose();
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AssetScannerScreen()),
    );
    if (code != null && mounted) {
      setState(() {
        _serialCtrl.text = code;
      });
    }
  }

  void _nextStep() {
    if (_step == 0) {
      if (_selectedSensorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione manualmente um sensor na lista.'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 2);
      return;
    }
  }

  Future<void> _startDiagnostic() async {
    final controller = BenchScope.of(context);
    if (!controller.hasIdentity) {
      final ok = await showIdentityDialog(context, controller, required: true);
      if (!ok || !mounted) return;
    }
    if (!await confirmTechnicianPin(context, controller) || !mounted) return;
    final tech = controller.technicianLabel;

    final LiveTelemetry? sensor =
        _selectedSensorId == null ? null : controller.telemetryForSensor(_selectedSensorId!);
    if (sensor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sensor selecionado não encontrado. Volte ao Passo 1.'),
          backgroundColor: AppColors.fault,
        ),
      );
      return;
    }

    setState(() => _starting = true);
    try {
      final session = await controller.startSession(
        sensor: sensor,
        serialNumber: _serialCtrl.text.trim(),
        modelName: _modelCtrl.text.trim(),
        technicianName: tech,
        profile: _selectedProfile,
        reportedSymptom: _symptomCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DiagnosticLiveScreen(sessionId: session.id),
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
      setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final sensors = controller.discoveredSensors;
    final selectedSensor = _selectedSensorId == null
        ? null
        : controller.telemetryForSensor(_selectedSensorId!);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: () {
            if (_step > 0 && widget.preselectedSensorId == null) {
              setState(() => _step--);
            } else if (_step > 1 && widget.preselectedSensorId != null) {
              setState(() => _step--);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text('Vincular e Iniciar Ensaio'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _WizardStepBar(currentStep: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: _buildStepBody(sensors, selectedSensor, controller),
              ),
            ),
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
              if (_step > 0) ...[
                OutlinedButton(
                  onPressed: _starting ? null : () => setState(() => _step--),
                  child: const Text('Voltar'),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _step < 2
                    ? FilledButton.icon(
                        onPressed: _nextStep,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                            _step == 0 ? 'Continuar para Equipamento' : 'Revisar T0 e Iniciar'),
                      )
                    : ElevatedButton.icon(
                        onPressed: _starting ? null : _startDiagnostic,
                        icon: _starting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _starting
                              ? 'Iniciando...'
                              : 'Iniciar Diagnóstico (T0)',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody(
    List<LiveTelemetry> sensors,
    LiveTelemetry? selectedSensor,
    BenchController controller,
  ) {
    if (_step == 0) {
      final hiddenFar = controller.hiddenDistantSensorsCount;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '1. Selecione o sensor térmico manual',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => controller.startRadar(restart: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Buscar'),
              ),
            ],
          ),
          const Text(
            'Nenhuma conexão automática é feita. Toque no sensor instalado dentro da geladeira em teste.',
            style: TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilterChip(
                selected: controller.filterStrongOnly,
                showCheckmark: true,
                label: Text(
                  controller.filterStrongOnly
                      ? 'Apenas Próximos (Sinal Forte ≥ ${BenchController.strongRssiThreshold} dBm)'
                      : 'Todos os Sensores Detectados',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: controller.filterStrongOnly ? AppColors.indigo : AppColors.ink,
                  ),
                ),
                onSelected: (val) => controller.setFilterStrongOnly(val),
              ),
            ],
          ),
          if (_isAndroid) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.indigoSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.nfc_rounded, size: 18, color: AppColors.indigo),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Android: Selecione na lista BLE ou use a etiqueta de patrimônio QR no próximo passo.',
                      style: TextStyle(fontSize: 12, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (sensors.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    const Icon(Icons.bluetooth_searching_rounded,
                        size: 40, color: AppColors.muted),
                    const SizedBox(height: 10),
                    const Text(
                      'Aguardando sensores próximos...',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.filterStrongOnly
                          ? 'Aproxime o celular do sensor da geladeira (sinal forte ≥ ${BenchController.strongRssiThreshold} dBm).'
                          : 'Aguardando qualquer sensor Wellington/AoFrio anunciar.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
                    ),
                    if (hiddenFar > 0) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => controller.setFilterStrongOnly(false),
                        child: Text('Exibir $hiddenFar sensor(es) distantes'),
                      ),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => controller.startRadar(restart: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Atualizar Busca'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...sensors.map((s) {
              final inUse = controller.activeSessionForSensor(s.deviceId);
              final isSelected = _selectedSensorId == s.deviceId;
              final isSim = s.deviceId.startsWith('SIM-');
              final signalDesc = s.rssi >= -65
                  ? 'Forte'
                  : (s.rssi >= BenchController.strongRssiThreshold ? 'Bom' : 'Distante');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? AppColors.indigo : AppColors.line,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    enabled: inUse == null,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? AppColors.indigo
                          : (isSim ? AppColors.warningBg : AppColors.cryoSoft),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : (isSim
                                ? Icons.science_rounded
                                : Icons.sensors_rounded),
                        color: isSelected
                            ? Colors.white
                            : (isSim ? AppColors.warning : AppColors.cryo),
                      ),
                    ),
                    title: Text(
                      s.assetName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      inUse != null
                          ? 'Em uso por ${inUse.serialNumber}'
                          : 'Sinal $signalDesc (${s.rssi} dBm)${isSim ? ' • SIMULAÇÃO' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      s.temperatureC == null
                          ? '—'
                          : '${s.temperatureC!.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    onTap: inUse != null
                        ? null
                        : () => setState(() => _selectedSensorId = s.deviceId),
                  ),
                ),
              );
            }),
          if (hiddenFar > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$hiddenFar sensor(es) distantes ocultados para evitar confusão.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.setFilterStrongOnly(!controller.filterStrongOnly),
                    child: Text(controller.filterStrongOnly ? 'Ver todos' : 'Ocultar distantes'),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    if (_step == 1) {
      return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '2. Identificação do equipamento e norma',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sensor selecionado: ${selectedSensor?.assetName ?? _selectedSensorId}',
              style: const TextStyle(
                color: AppColors.indigo,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _serialCtrl,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Informe o patrimônio ou série.' : null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Patrimônio / Nº de Série da geladeira',
                hintText: 'Ex.: BR-449012 ou leia o QR Code',
                prefixIcon: const Icon(Icons.qr_code_2_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Ler QR Code pela câmera',
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _modelCtrl,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Informe o modelo do equipamento.' : null,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Modelo do refrigerador',
                prefixIcon: Icon(Icons.kitchen_outlined),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Perfil de teste',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            ...TestProfile.defaultProfiles.map((p) {
              final selected = p.id == _selectedProfile.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: selected ? AppColors.indigo : AppColors.line,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selectedProfile = p),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selected ? AppColors.indigo : AppColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  'Meta ${p.targetTemperature}°C • Prazo ${p.manualMaxAllowedMinutes ?? 180} min • T0 mín ${p.minStartingAmbientTemp}°C',
                                  style: const TextStyle(
                                      fontSize: 11.5, color: AppColors.slate),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    // Passo 3: Técnico, sintoma relatado e Auditoria T0 ao vivo
    final t0 = selectedSensor?.temperatureC;
    final t0Valid = t0 != null && t0 >= _selectedProfile.minStartingAmbientTemp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '3. Responsável, queixa e auditoria de partida (T0)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.badge_outlined, color: AppColors.indigo),
            title: const Text(
              'Técnico responsável pelo ensaio',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            subtitle: Text(
              controller.hasIdentity ? controller.technicianLabel : 'Não identificado',
            ),
            trailing: TextButton(
              onPressed: () async {
                await showIdentityDialog(context, controller);
                if (mounted) setState(() {});
              },
              child: Text(controller.hasIdentity ? 'Trocar' : 'Informar'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _symptomCtrl,
          decoration: const InputDecoration(
            labelText: 'Queixa relatada / defeito observado (opcional)',
            hintText: 'Ex.: Não gela, placa trocada, suspeita de vazamento',
            prefixIcon: Icon(Icons.report_problem_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _commonSymptoms.map((s) {
            return ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 11.5)),
              onPressed: () => setState(() => _symptomCtrl.text = s),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    t0Valid
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                    color: t0Valid ? AppColors.approvedBright : AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Auditoria de Temperatura Inicial (T0)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    t0 == null ? '—' : '${t0.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t0 == null
                          ? 'Aguardando leitura do sensor...'
                          : (t0Valid
                              ? 'Baseline validado em repouso térmico (≥ ${_selectedProfile.minStartingAmbientTemp}°C).'
                              : 'Abaixo de ${_selectedProfile.minStartingAmbientTemp}°C: o sistema registrará como partida pré-resfriada.'),
                      style: TextStyle(
                        color: t0Valid
                            ? AppColors.approvedBright
                            : AppColors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.slateDark),
              const SizedBox(height: 8),
              Text(
                'Equipamento: ${_serialCtrl.text.trim()} (${_modelCtrl.text.trim()})\n'
                'Norma: ${_selectedProfile.name}\n'
                'Meta: ${_selectedProfile.targetTemperature}°C em até ${_selectedProfile.manualMaxAllowedMinutes ?? 180} min • Porta fechada.',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WizardStepBar extends StatelessWidget {
  final int currentStep;
  const _WizardStepBar({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['1. Sensor', '2. Equipamento', '3. Auditoria T0'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= currentStep;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: active ? AppColors.indigo : AppColors.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? AppColors.indigo : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
