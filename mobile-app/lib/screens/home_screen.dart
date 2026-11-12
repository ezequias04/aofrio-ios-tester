import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/pull_down_analyzer.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../services/ble_service_interface.dart';
import '../services/local_report_store.dart';
import '../services/mock_ble_service.dart';
import '../services/wellington_ble_service.dart';
import '../theme/app_theme.dart';
import 'asset_scanner_screen.dart';
import 'test_report_screen.dart';

class HomeScreen extends StatefulWidget {
  final IBleService initialBleService;
  const HomeScreen({super.key, required this.initialBleService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _modelController = TextEditingController();
  final _technicianController = TextEditingController();
  TestProfile _selectedProfile = TestProfile.defaultProfiles.first;
  late IBleService _currentBleService;
  bool _useRealBle = false;
  bool _isLoading = false;
  int _localReportCount = 0;
  String _statusText = 'Pronto para iniciar';

  @override
  void initState() {
    super.initState();
    _currentBleService = widget.initialBleService;
    _serialController.text = 'BR-AOFRIO-9821';
    _modelController.text = 'Expositor Comercial 450L (Metalfrio)';
    _technicianController.text = 'Técnico Pereira';
    _loadLocalCount();
  }

  Future<void> _loadLocalCount() async {
    final count = await LocalReportStore.count();
    if (mounted) setState(() => _localReportCount = count);
  }

  @override
  void dispose() {
    _serialController.dispose();
    _modelController.dispose();
    _technicianController.dispose();
    unawaited(_currentBleService.disconnect());
    super.dispose();
  }

  void _fillSampleData() {
    setState(() {
      _serialController.text = 'BR-AOFRIO-9821';
      _modelController.text = 'Expositor Comercial 450L (Metalfrio)';
      _technicianController.text = 'Técnico Pereira';
    });
    _formKey.currentState?.validate();
  }

  void _toggleBleMode(bool real) {
    if (_useRealBle == real) return;
    unawaited(_currentBleService.disconnect());
    setState(() {
      _useRealBle = real;
      _currentBleService = real ? WellingtonBleService() : MockBleService();
    });
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Preencha este campo.';
    return null;
  }

  Future<void> _scanAsset() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AssetScannerScreen()),
    );
    if (value != null && mounted) {
      _serialController.text = value;
      _formKey.currentState?.validate();
    }
  }

  Future<void> _showSavedReportsModal() async {
    final reports = await LocalReportStore.getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.all(20),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Laudos Salvos no Aparelho',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (reports.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Nenhum laudo salvo offline ainda.\nExecute um ensaio para registrar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.slate),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: reports.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final r = reports[index];
                            final passed = r.status == TestStatus.aprovada;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: passed ? AppColors.ice : const Color(0xFFFFEBEE),
                                child: Icon(
                                  passed ? Icons.check_circle : Icons.cancel,
                                  color: passed ? AppColors.success : AppColors.danger,
                                ),
                              ),
                              title: Text(
                                '${r.serialNumber} • ${r.modelName}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Text(
                                '${r.durationMinutes} min • ${r.finalTemp}°C • ${r.technicianName}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.slate),
                                onPressed: () async {
                                  await LocalReportStore.delete(r.testId);
                                  reports.removeAt(index);
                                  setModalState(() {});
                                  _loadLocalCount();
                                },
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => TestReportScreen(result: r)),
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _runAudit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _statusText = _useRealBle ? 'Procurando sensor próximo…' : 'Calculando ensaio pull-down…';
    });

    try {
      if (_useRealBle) {
        await _ensureBluetoothPermissions();
        final devices = await _currentBleService
            .scanForDevices()
            .firstWhere((items) => items.isNotEmpty)
            .timeout(const Duration(seconds: 12));
        await _currentBleService.stopScan();
        devices.sort((a, b) => b.rssi.compareTo(a.rssi));
        final device = devices.first;
        _setStatus('Conectando a ${device.name}…');
        final connected = await _currentBleService.connect(device.id);
        if (!connected) throw Exception('O sensor recusou a conexão Bluetooth.');
      } else {
        await _currentBleService.connect('MOCK-DEVICE');
      }

      _setStatus('Baixando histórico do sensor…');
      final readings = await _currentBleService.downloadStoredHistory();
      if (readings.isEmpty) throw Exception('O sensor não retornou leituras para analisar.');
      _setStatus('Analisando a curva térmica ISO 23953…');
      final result = PullDownAnalyzer.analyze(
        serialNumber: _serialController.text.trim(),
        modelName: _modelController.text.trim(),
        technicianName: _technicianController.text.trim(),
        profile: _selectedProfile,
        readings: readings,
      );
      await LocalReportStore.save(result);
      await _currentBleService.disconnect();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TestReportScreen(result: result)),
      );
      await _loadLocalCount();
    } on TimeoutException {
      _showTimeoutWithSimulatorOption();
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      await _currentBleService.stopScan();
      await _currentBleService.disconnect();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = 'Pronto para iniciar';
        });
      }
    }
  }

  void _showTimeoutWithSimulatorOption() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text('Nenhum sensor físico AoFrio encontrado por perto.'),
      backgroundColor: AppColors.slate,
      action: SnackBarAction(
        label: 'Testar com Simulador',
        textColor: AppColors.ocean,
        onPressed: () {
          _toggleBleMode(false);
          _runAudit();
        },
      ),
    ));
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _statusText = value);
  }

  Future<void> _ensureBluetoothPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied = statuses.values.any((status) => status.isDenied || status.isPermanentlyDenied);
    if (denied) {
      throw Exception('Autorize Bluetooth e dispositivos próximos nas configurações para localizar o sensor.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.danger,
      action: SnackBarAction(label: 'Fechar', textColor: Colors.white, onPressed: () {}),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          _BrandMark(), SizedBox(width: 11), Text('AoFrio Test'),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: InkWell(
                onTap: _showSavedReportsModal,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_outlined, size: 16, color: AppColors.ocean),
                      const SizedBox(width: 6),
                      Text('$_localReportCount salvos', style: const TextStyle(color: AppColors.ocean, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 920;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal ? 32 : 18, 18, horizontal ? 32 : 18, 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const _WelcomeHeader(),
                    const SizedBox(height: 24),
                    if (horizontal)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _buildIdentificationCard()),
                        const SizedBox(width: 18),
                        Expanded(child: _buildTestCard()),
                      ])
                    else ...[
                      _buildIdentificationCard(),
                      const SizedBox(height: 16),
                      _buildTestCard(),
                    ],
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: Center(
            heightFactor: 1, // sem isso a barra ocupa a tela inteira e esconde o formulário
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runAudit,
                icon: _isLoading
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Icon(_useRealBle ? Icons.bluetooth_searching : Icons.play_arrow_rounded),
                label: Text(
                  _isLoading
                      ? _statusText
                      : (_useRealBle ? 'Conectar ao Sensor e Avaliar' : 'Executar Ensaio Pull-Down'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentificationCard() => _SectionCard(
    title: 'Identificação do equipamento',
    subtitle: 'Dados que serão impressos no laudo oficial.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: _serialController,
        validator: _required,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'Patrimônio ou número de série',
          prefixIcon: const Icon(Icons.qr_code_2),
          suffixIcon: IconButton(onPressed: _isLoading ? null : _scanAsset, tooltip: 'Ler QR Code', icon: const Icon(Icons.document_scanner_outlined)),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _modelController,
        validator: _required,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Modelo do refrigerador', prefixIcon: Icon(Icons.kitchen_outlined)),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _technicianController,
        validator: _required,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Técnico responsável', prefixIcon: Icon(Icons.badge_outlined)),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _fillSampleData,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Restaurar dados de teste', style: TextStyle(fontSize: 12)),
        ),
      ),
    ]),
  );

  Widget _buildTestCard() {
    final mock = !_useRealBle && _currentBleService is MockBleService ? _currentBleService as MockBleService : null;
    return _SectionCard(
      title: 'Configuração do ensaio',
      subtitle: 'Escolha a fonte dos dados e o perfil térmico.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.science_outlined), label: Text('Simulador')),
            ButtonSegment(value: true, icon: Icon(Icons.bluetooth), label: Text('Sensor BLE')),
          ],
          selected: {_useRealBle},
          onSelectionChanged: _isLoading ? null : (selection) => _toggleBleMode(selection.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 14),
        _ConnectionBanner(real: _useRealBle),
        const SizedBox(height: 14),
        DropdownButtonFormField<TestProfile>(
          initialValue: _selectedProfile,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Perfil térmico', prefixIcon: Icon(Icons.thermostat_outlined)),
          items: TestProfile.defaultProfiles.map((profile) => DropdownMenuItem(
            value: profile,
            child: Text('${profile.name.split(' (').first} • ${profile.targetTemperature}°C', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: _isLoading ? null : (value) => setState(() => _selectedProfile = value ?? _selectedProfile),
        ),
        if (mock != null) ...[
          const SizedBox(height: 16),
          const Text('Cenário de simulação:', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _scenarioChip(mock, MockScenario.refrigeratorPass, 'Aprovação Normal'),
            _scenarioChip(mock, MockScenario.refrigeratorFailGas, 'Falha de Gás'),
            _scenarioChip(mock, MockScenario.doorViolation, 'Porta Aberta'),
          ]),
        ],
      ]),
    );
  }

  Widget _scenarioChip(MockBleService service, MockScenario scenario, String label) => ChoiceChip(
    label: Text(label),
    selected: service.currentScenario == scenario,
    onSelected: _isLoading ? null : (_) => setState(() => service.currentScenario = scenario),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(color: AppColors.ocean, borderRadius: BorderRadius.circular(13)),
    child: const Icon(Icons.ac_unit_rounded, color: Colors.white, size: 21),
  );
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFCBE9EB))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ENSAIO PULL-DOWN ISO 23953', style: TextStyle(color: AppColors.ocean, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 7),
        Text('Qualificação Térmica Direta no Refrigerador.', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('O app conecta ao sensor BLE ou roda o ensaio localmente mesmo sem internet.'),
      ])),
      const SizedBox(width: 14),
      const Icon(Icons.show_chart_rounded, size: 54, color: AppColors.ocean),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _SectionCard({required this.title, required this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle),
        const SizedBox(height: 18),
        child,
      ]),
    ),
  );
}

class _ConnectionBanner extends StatelessWidget {
  final bool real;
  const _ConnectionBanner({required this.real});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: real ? AppColors.ice : const Color(0xFFF2F5F8), borderRadius: BorderRadius.circular(15)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(real ? Icons.bluetooth_searching : Icons.offline_bolt_outlined, color: real ? AppColors.ocean : AppColors.slate),
      const SizedBox(width: 11),
      Expanded(child: Text(
        real
            ? 'O app buscará o sensor Wellington/AoFrio mais próximo e baixará o histórico armazenado.'
            : 'Simulação instantânea com dados normativos de curva pull-down (funciona sem hardware).',
        style: const TextStyle(fontSize: 13),
      )),
    ]),
  );
}
