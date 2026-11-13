import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/test_profile.dart';
import '../models/test_session.dart';
import '../services/ble_service_interface.dart';
import '../theme/app_theme.dart';
import 'asset_scanner_screen.dart';

class EquipmentLinkWizardDialog extends StatefulWidget {
  final IBleService bleService;
  final bool isSimulation;
  final List<String> alreadyLinkedSensorIds;

  const EquipmentLinkWizardDialog({
    super.key,
    required this.bleService,
    required this.isSimulation,
    this.alreadyLinkedSensorIds = const [],
  });

  @override
  State<EquipmentLinkWizardDialog> createState() => _EquipmentLinkWizardDialogState();
}

class _EquipmentLinkWizardDialogState extends State<EquipmentLinkWizardDialog> {
  int _currentStep = 0; // 0 = Sensor, 1 = Equipamento, 2 = Responsável

  // Passo 1: Dispositivo Sensor
  DiscoveredDevice? _selectedDevice;
  List<DiscoveredDevice> _discoveredDevices = [];
  bool _isScanning = false;
  StreamSubscription? _scanSubscription;
  int _sensorMethodTab = 0; // 0 = Bluetooth LE, 1 = NFC (Android apenas)
  bool _isNfcWaiting = false;

  // Passo 2: Equipamento / Geladeira
  final _serialController = TextEditingController();
  final _modelController = TextEditingController(text: 'Expositor Comercial 450L');
  TestProfile _selectedProfile = TestProfile.defaultProfiles.first;

  // Passo 3: Responsável & Duração
  final _technicianController = TextEditingController(text: 'Técnico Pereira');
  Duration _selectedDuration = const Duration(minutes: 30);

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isIos => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _serialController.dispose();
    _modelController.dispose();
    _technicianController.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _discoveredDevices = [];
    });

    _scanSubscription?.cancel();
    _scanSubscription = widget.bleService.scanForDevices().listen((devices) {
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
          _isScanning = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });

    // Se estiver em modo real, encerra o scan após 10 segundos
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _simulateNfcRead() {
    setState(() => _isNfcWaiting = true);
    // Simula leitura de tag NFC do sensor Wellington
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final nfcDevice = DiscoveredDevice(
        id: 'AOFRIO-NFC-${DateTime.now().millisecondsSinceEpoch % 10000}',
        name: 'AoFrio SCS (NFC Tag)',
        rssi: -45,
      );
      setState(() {
        _isNfcWaiting = false;
        _selectedDevice = nfcDevice;
        _currentStep = 1; // Avança para o equipamento
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sensor identificado via NFC: ${nfcDevice.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    });
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AssetScannerScreen()),
    );
    if (code != null && code.trim().isNotEmpty && mounted) {
      setState(() {
        _serialController.text = code.trim();
      });
    }
  }

  void _finishAndLink() {
    final serial = _serialController.text.trim();
    final model = _modelController.text.trim();
    final tech = _technicianController.text.trim();

    if (serial.isEmpty) {
      _showToast('Informe o patrimônio do equipamento.');
      setState(() => _currentStep = 1);
      return;
    }

    if (model.isEmpty) {
      _showToast('Informe o modelo do equipamento.');
      setState(() => _currentStep = 1);
      return;
    }

    if (tech.isEmpty) {
      _showToast('Informe o técnico responsável pelo teste.');
      return;
    }

    final session = TestSession(
      id: 'SESS-${DateTime.now().millisecondsSinceEpoch}',
      equipmentSerial: serial,
      equipmentModel: model,
      technicianName: tech,
      profile: _selectedProfile,
      sensorDevice: _selectedDevice!,
      startTime: DateTime.now(),
      targetDuration: _selectedDuration,
      currentTemperature: 24.0 + (DateTime.now().second % 6) * 0.5,
    );

    Navigator.of(context).pop(session);
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.warning),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Column(
          children: [
            // Cabeçalho com indicador de progresso (Sem botão X)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Vincular Equipamento',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.ice,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Passo ${_currentStep + 1} de 3',
                          style: const TextStyle(
                            color: AppColors.ocean,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Barra de passos
                  Row(
                    children: [
                      _StepBar(active: _currentStep >= 0, title: '1. Sensor'),
                      const SizedBox(width: 8),
                      _StepBar(active: _currentStep >= 1, title: '2. Geladeira'),
                      const SizedBox(width: 8),
                      _StepBar(active: _currentStep >= 2, title: '3. Técnico'),
                    ],
                  ),
                ],
              ),
            ),

            // Conteúdo dinâmico do passo atual
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildStepContent(),
              ),
            ),

            // Rodapé com botões de navegação (Voltar / Avançar / Cancelar - Sem X)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  if (_currentStep == 0)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => setState(() => _currentStep--),
                      child: const Text('Voltar'),
                    ),
                  const Spacer(),
                  if (_currentStep < 2)
                    FilledButton(
                      onPressed: _canAdvance()
                          ? () => setState(() => _currentStep++)
                          : null,
                      child: const Text('Próximo'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _finishAndLink,
                      icon: const Icon(Icons.check),
                      label: const Text('Vincular & Iniciar Ensaio'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvance() {
    if (_currentStep == 0) {
      return _selectedDevice != null;
    }
    if (_currentStep == 1) {
      return _serialController.text.trim().isNotEmpty &&
          _modelController.text.trim().isNotEmpty;
    }
    return true;
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Sensor();
      case 1:
        return _buildStep2Equipment();
      case 2:
        return _buildStep3Technician();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── ETAPA 1: SELECIONAR SENSOR ──────────────────────────────────────────────
  Widget _buildStep1Sensor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Selecione o Sensor AoFrio / Wellington',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'O app não conecta automaticamente. Selecione manualmente o sensor que está instalado na geladeira.',
          style: TextStyle(fontSize: 13, color: AppColors.slate),
        ),
        const SizedBox(height: 16),

        // Se for Android, mostra abas Bluetooth LE vs NFC
        if (_isAndroid) ...[
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Bluetooth LE'), icon: Icon(Icons.bluetooth)),
              ButtonSegment(value: 1, label: Text('Aproximar por NFC'), icon: Icon(Icons.nfc)),
            ],
            selected: {_sensorMethodTab},
            onSelectionChanged: (set) => setState(() => _sensorMethodTab = set.first),
          ),
          const SizedBox(height: 16),
        ] else if (_isIos) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.ice,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.bluetooth, color: AppColors.ocean, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No iOS, a comunicação com o sensor é realizada via Bluetooth LE.',
                    style: TextStyle(fontSize: 12, color: AppColors.ocean, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_sensorMethodTab == 1 && _isAndroid)
          _buildNfcPanel()
        else
          _buildBleList(),
      ],
    );
  }

  Widget _buildNfcPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.nfc, size: 64, color: AppColors.ocean),
          const SizedBox(height: 16),
          const Text(
            'Aproxime o celular do sensor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            'Encoste a traseira do smartphone na etiqueta NFC do sensor Wellington AoFrio para vincular instantaneamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.slate),
          ),
          const SizedBox(height: 20),
          if (_isNfcWaiting)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Aguardando aproximação...', style: TextStyle(color: AppColors.ocean)),
              ],
            )
          else
            FilledButton.icon(
              onPressed: _simulateNfcRead,
              icon: const Icon(Icons.tap_and_play),
              label: const Text('Simular Toque NFC (Identificar)'),
            ),
        ],
      ),
    );
  }

  Widget _buildBleList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dispositivos Detectados (${_discoveredDevices.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.slate),
            ),
            TextButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_isScanning ? 'Buscando...' : 'Atualizar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_discoveredDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.bluetooth_searching, size: 40, color: AppColors.slate),
                  const SizedBox(height: 12),
                  const Text(
                    'Nenhum sensor encontrado ainda.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Certifique-se de que o sensor AoFrio está alimentado e próximo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.slate),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startScan,
                    child: const Text('Escanear Novamente'),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _discoveredDevices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final dev = _discoveredDevices[index];
              final isSelected = _selectedDevice?.id == dev.id;
              final isAlreadyLinked = widget.alreadyLinkedSensorIds.contains(dev.id);

              return InkWell(
                onTap: isAlreadyLinked
                    ? null
                    : () {
                        setState(() => _selectedDevice = dev);
                      },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.ice : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.ocean : AppColors.line,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isSelected ? AppColors.ocean : const Color(0xFFF1F5F9),
                        child: Icon(
                          Icons.sensors,
                          color: isSelected ? Colors.white : AppColors.ocean,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dev.name.isEmpty ? 'Sensor AoFrio (Sem Nome)' : dev.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'ID: ${dev.id}',
                              style: const TextStyle(color: AppColors.slate, fontSize: 12, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      if (isAlreadyLinked)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Em uso',
                            style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        )
                      else ...[
                        Text(
                          '${dev.rssi} dBm',
                          style: const TextStyle(color: AppColors.slate, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Radio<String>(
                          value: dev.id,
                          groupValue: _selectedDevice?.id,
                          onChanged: (val) {
                            setState(() => _selectedDevice = dev);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ── ETAPA 2: VINCULAR EQUIPAMENTO / GELADEIRA ───────────────────────────────
  Widget _buildStep2Equipment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card do sensor selecionado
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ice,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ocean.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.ocean),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sensor Vinculado:', style: TextStyle(fontSize: 11, color: AppColors.slate)),
                    Text(
                      '${_selectedDevice?.name} (${_selectedDevice?.id})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('Trocar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'Identificação do Equipamento / Geladeira',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'Leia o QR Code do ativo ou digite o número do patrimônio da geladeira.',
          style: TextStyle(fontSize: 13, color: AppColors.slate),
        ),
        const SizedBox(height: 16),

        // Campo Patrimônio + Botão QR Code
        TextFormField(
          controller: _serialController,
          decoration: InputDecoration(
            labelText: 'Patrimônio / Nº de Série da Geladeira *',
            hintText: 'Ex.: BR-AOFRIO-9821 ou 048291',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: AppColors.ocean),
              tooltip: 'Escanear QR Code com a câmera',
              onPressed: _scanBarcode,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),

        // Botão dedicado de leitura de QR Code
        OutlinedButton.icon(
          onPressed: _scanBarcode,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Escanear QR Code com a Câmera'),
        ),
        const SizedBox(height: 16),

        // Modelo da Geladeira
        TextFormField(
          controller: _modelController,
          decoration: const InputDecoration(
            labelText: 'Modelo do Equipamento *',
            hintText: 'Ex.: Expositor Metalfrio 450L',
            prefixIcon: const Icon(Icons.kitchen),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),

        // Sugestões de Modelos
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Expositor 450L'),
              onPressed: () => setState(() => _modelController.text = 'Expositor Comercial 450L'),
            ),
            ActionChip(
              label: const Text('Cervejeira Dupla'),
              onPressed: () => setState(() => _modelController.text = 'Cervejeira Dupla Porta 500L'),
            ),
            ActionChip(
              label: const Text('Freezer Horizontal'),
              onPressed: () => setState(() => _modelController.text = 'Freezer Horizontal 300L'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Perfil Térmico ISO 23953
        DropdownButtonFormField<TestProfile>(
          value: _selectedProfile,
          decoration: const InputDecoration(
            labelText: 'Perfil de Ensaio Térmico (ISO 23953)',
            prefixIcon: Icon(Icons.thermostat),
          ),
          items: TestProfile.defaultProfiles.map((p) {
            return DropdownMenuItem(
              value: p,
              child: Text('${p.name} (${p.minTemperature}°C a ${p.maxTemperature}°C)'),
            );
          }).toList(),
          onChanged: (p) {
            if (p != null) setState(() => _selectedProfile = p);
          },
        ),
      ],
    );
  }

  // ── ETAPA 3: RESPONSÁVEL & DURAÇÃO ──────────────────────────────────────────
  Widget _buildStep3Technician() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Responsável e Parâmetros do Ensaio',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'Indique quem está executando a qualificação técnica para constar no laudo oficial.',
          style: TextStyle(fontSize: 13, color: AppColors.slate),
        ),
        const SizedBox(height: 20),

        // Técnico Responsável
        TextFormField(
          controller: _technicianController,
          decoration: const InputDecoration(
            labelText: 'Nome do Técnico / Inspetor *',
            hintText: 'Ex.: Técnico Pereira',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // Janela de Duração do Teste
        DropdownButtonFormField<Duration>(
          value: _selectedDuration,
          decoration: const InputDecoration(
            labelText: 'Tempo de Monitoramento / Pull-Down',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
          items: const [
            DropdownMenuItem(value: Duration(minutes: 15), child: Text('15 min (teste rápido de bancada)')),
            DropdownMenuItem(value: Duration(minutes: 30), child: Text('30 min (padrão de qualificação)')),
            DropdownMenuItem(value: Duration(hours: 1), child: Text('1 hora')),
            DropdownMenuItem(value: Duration(hours: 2), child: Text('2 horas (pull-down completo)')),
          ],
          onChanged: (d) {
            if (d != null) setState(() => _selectedDuration = d);
          },
        ),
        const SizedBox(height: 20),

        // Check de Prontidão de Auditoria (Ponto T0)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified, size: 18, color: AppColors.success),
                  SizedBox(width: 8),
                  Text(
                    'CHECK DE PRONTIDÃO DE AUDITORIA (PONTO T0)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.success, letterSpacing: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Gabinete em repouso térmico verificado (Baseline ≥ ${_selectedProfile.minStartingAmbientTemp}°C)\n'
                '• Intertravamento de porta fechada monitorado pelo sensor AoFrio\n'
                '• Inflexão térmica e tempo oficial cravados na memória flash',
                style: const TextStyle(fontSize: 12, color: AppColors.ink, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Resumo do Vínculo
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RESUMO DO VÍNCULO',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.slate, letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              _SummaryRow(label: 'Sensor:', value: '${_selectedDevice?.name} (${_selectedDevice?.id})'),
              _SummaryRow(label: 'Equipamento:', value: '${_serialController.text} • ${_modelController.text}'),
              _SummaryRow(label: 'Norma / Padrão:', value: _selectedProfile.standardName),
              _SummaryRow(label: 'Setpoint Alvo:', value: '${_selectedProfile.targetTemperature}°C (Faixa: ${_selectedProfile.minTemperature}°C a ${_selectedProfile.maxTemperature}°C)'),
              _SummaryRow(label: 'Responsável:', value: _technicianController.text),
              _SummaryRow(label: 'Duração:', value: '${_selectedDuration.inMinutes} minutos'),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBar extends StatelessWidget {
  final bool active;
  final String title;

  const _StepBar({required this.active, required this.title});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: active ? AppColors.ocean : AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? AppColors.ocean : AppColors.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slate, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}
