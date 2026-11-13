import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/pull_down_analyzer.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../services/local_report_store.dart';
import '../services/wellington_ble_service.dart';
import '../theme/app_theme.dart';
import 'asset_scanner_screen.dart';
import 'live_monitor_screen.dart';
import 'test_report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _modelController = TextEditingController();
  final _responsibleController = TextEditingController();
  TestProfile _selectedProfile = TestProfile.defaultProfiles.first;

  /// Janela de captura ao vivo do ensaio pull-down (o sensor transmite a
  /// temperatura no anúncio BLE; o app grava a curva durante este tempo).
  /// Pode minimizar o app durante o ensaio — continua lendo em segundo plano.
  static const _captureWindows = <String, Duration>{
    '2 min (teste rápido)': Duration(minutes: 2),
    '15 min': Duration(minutes: 15),
    '30 min': Duration(minutes: 30),
    '1 hora': Duration(hours: 1),
    '2 horas (pull-down completo)': Duration(hours: 2),
  };
  Duration _captureWindow = const Duration(minutes: 30);

  final WellingtonBleService _ble = WellingtonBleService();
  bool _isLoading = false;
  int _localReportCount = 0;
  String _statusText = 'Pronto para iniciar';

  @override
  void initState() {
    super.initState();
    _serialController.text = 'BR-AOFRIO-9821';
    _modelController.text = 'Expositor Comercial 450L (Metalfrio)';
    _responsibleController.text = 'Pereira';
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
    _responsibleController.dispose();
    unawaited(_ble.disconnect());
    super.dispose();
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

  Future<void> _openLiveMonitor() async {
    try {
      await _ensureBluetoothPermissions();
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveMonitorScreen(service: _ble)),
    );
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
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
                                child: Icon(passed ? Icons.check_circle : Icons.cancel, color: passed ? AppColors.success : AppColors.danger),
                              ),
                              title: Text('${r.serialNumber} • ${r.modelName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('${r.durationMinutes} min • ${r.finalTemp}°C • ${r.technicianName}', style: const TextStyle(fontSize: 12)),
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
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestReportScreen(result: r)));
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
      _statusText = 'Procurando sensor próximo…';
    });

    try {
      await _ensureBluetoothPermissions();
      final devices = await _ble
          .scanForDevices()
          .firstWhere((items) => items.isNotEmpty)
          .timeout(const Duration(seconds: 12));
      await _ble.stopScan();
      devices.sort((a, b) => b.rssi.compareTo(a.rssi));
      final device = devices.first;
      _setStatus('Conectando a ${device.name}…');
      final connected = await _ble.connect(device.id);
      if (!connected) throw Exception('O sensor recusou a conexão Bluetooth.');

      _ble.liveCaptureWindow = _captureWindow;
      _setStatus('Gravando curva ao vivo por ${_captureWindow.inMinutes} min… pode minimizar o app.');
      final readings = await _ble.downloadStoredHistory();
      if (readings.isEmpty) {
        await _showBleDiagnostic(_ble.rawLog.join('\n'));
        return;
      }
      _setStatus('Analisando a curva térmica ISO 23953…');
      final result = PullDownAnalyzer.analyze(
        serialNumber: _serialController.text.trim(),
        modelName: _modelController.text.trim(),
        technicianName: _responsibleController.text.trim(),
        profile: _selectedProfile,
        readings: readings,
      );
      await LocalReportStore.save(result);
      await _ble.disconnect();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestReportScreen(result: result)));
      await _loadLocalCount();
    } on TimeoutException {
      _showNoSensorFound();
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      await _ble.stopScan();
      await _ble.disconnect();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = 'Pronto para iniciar';
        });
      }
    }
  }

  Future<void> _showBleDiagnostic(String log) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sensor conectou, mas não enviou leituras'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                'Toque em "Copiar diagnóstico" e envie o texto para o suporte. '
                'Ele mostra os bytes que o sensor respondeu.\n\n$log',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar diagnóstico'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log));
                if (context.mounted) Navigator.of(context).pop();
                _showError('Diagnóstico copiado. Cole no WhatsApp/e-mail para enviar.');
              },
            ),
          ],
        ),
      );

  void _showNoSensorFound() {
    if (!mounted) return;
    final seen = _ble.lastSeenDevices;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(seen.isEmpty
          ? 'Nenhum aparelho Bluetooth encontrado. Confira se o Bluetooth está ligado e permitido para o app.'
          : 'Nenhum sensor AoFrio reconhecido. Aparelhos vistos:\n${seen.join('\n')}'),
      backgroundColor: AppColors.slate,
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
      backgroundColor: const Color(0xFFF6F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F9FB),
        surfaceTintColor: Colors.transparent,
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.folder_outlined, size: 16, color: AppColors.ocean),
                    const SizedBox(width: 6),
                    Text('$_localReportCount salvos', style: const TextStyle(color: AppColors.ocean, fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
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
            padding: EdgeInsets.fromLTRB(horizontal ? 32 : 18, 8, horizontal ? 32 : 18, 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _LiveTile(onTap: _isLoading ? null : _openLiveMonitor),
                    const SizedBox(height: 16),
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
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runAudit,
                icon: _isLoading
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(
                  _isLoading ? _statusText : 'Conectar ao Sensor e Avaliar',
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
            controller: _responsibleController,
            validator: _required,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Responsável pelo teste', prefixIcon: Icon(Icons.badge_outlined)),
          ),
        ]),
      );

  Widget _buildTestCard() => _SectionCard(
        title: 'Configuração do ensaio',
        subtitle: 'Perfil térmico e duração da captura ao vivo.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<TestProfile>(
            initialValue: _selectedProfile,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Perfil térmico', prefixIcon: Icon(Icons.thermostat_outlined)),
            items: TestProfile.defaultProfiles
                .map((profile) => DropdownMenuItem(
                      value: profile,
                      child: Text('${profile.name.split(' (').first} • ${profile.targetTemperature}°C', overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: _isLoading ? null : (value) => setState(() => _selectedProfile = value ?? _selectedProfile),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<Duration>(
            initialValue: _captureWindow,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Duração do ensaio ao vivo',
              helperText: 'Pode minimizar o app durante o ensaio.',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: _captureWindows.entries
                .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: _isLoading ? null : (value) => setState(() => _captureWindow = value ?? _captureWindow),
          ),
        ]),
      );
}

class _LiveTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _LiveTile({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.ocean,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.thermostat, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Temperatura em tempo real', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('Vê todos os sensores próximos ao vivo, sem conexão.', style: TextStyle(color: Color(0xFFD6EEF0), fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _SectionCard({required this.title, required this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
        ),
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
