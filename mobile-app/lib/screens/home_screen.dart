import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../models/test_session.dart';
import '../services/ble_service_interface.dart';
import '../services/local_report_store.dart';
import '../services/mock_ble_service.dart';
import '../services/wellington_ble_service.dart';
import '../theme/app_theme.dart';
import 'equipment_link_wizard_dialog.dart';
import 'session_live_screen.dart';
import 'standards_guide_screen.dart';
import 'test_report_screen.dart';

class HomeScreen extends StatefulWidget {
  final IBleService initialBleService;
  const HomeScreen({super.key, required this.initialBleService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late IBleService _currentBleService;
  bool _useRealBle = false;
  int _localReportCount = 0;

  // Bancada de testes: suporta múltiplos equipamentos monitorados simultaneamente
  final List<TestSession> _activeSessions = [];
  Timer? _benchTelemetryTimer;

  @override
  void initState() {
    super.initState();
    _currentBleService = widget.initialBleService;
    _loadLocalCount();
    _startBenchTelemetryTimer();
  }

  Future<void> _loadLocalCount() async {
    final count = await LocalReportStore.count();
    if (mounted) setState(() => _localReportCount = count);
  }

  @override
  void dispose() {
    _benchTelemetryTimer?.cancel();
    for (final s in _activeSessions) {
      s.dispose();
    }
    unawaited(_currentBleService.disconnect());
    super.dispose();
  }

  /// Timer central que atualiza as leituras térmicas dos equipamentos ativos
  void _startBenchTelemetryTimer() {
    _benchTelemetryTimer?.cancel();
    final random = Random();

    _benchTelemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _activeSessions.isEmpty) return;

      setState(() {
        for (final session in _activeSessions) {
          double newTemp = session.currentTemperature;

          if (!_useRealBle) {
            // Em modo simulação, reduz a temperatura gradualmente até o alvo
            final target = session.profile.targetTemperature;
            if (newTemp > target) {
              final drop = 0.25 + random.nextDouble() * 0.15;
              newTemp = max(target, newTemp - drop);
            } else {
              // Estabilização com leve oscilação natural
              newTemp = target + (sin(session.elapsedTime.inSeconds / 20.0) * 0.3);
            }
          }

          session.addReading(
            double.parse(newTemp.toStringAsFixed(1)),
            isDoorOpen: session.doorOpen,
            isCompOn: session.compressorOn,
          );
        }
      });
    });
  }

  void _toggleBleMode(bool real) {
    if (_useRealBle == real) return;
    unawaited(_currentBleService.disconnect());
    setState(() {
      _useRealBle = real;
      _currentBleService = real ? WellingtonBleService() : MockBleService();
    });
  }

  Future<void> _openLinkWizard() async {
    if (_useRealBle) {
      final bleGranted = await _ensureBluetoothPermissions();
      if (!bleGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ative as permissões de Bluetooth para buscar sensores físicos.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }

    if (!mounted) return;

    final alreadyLinkedIds = _activeSessions.map((s) => s.sensorDevice.id).toList();

    final newSession = await showDialog<TestSession>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EquipmentLinkWizardDialog(
        bleService: _currentBleService,
        isSimulation: !_useRealBle,
        alreadyLinkedSensorIds: alreadyLinkedIds,
      ),
    );

    if (newSession != null && mounted) {
      setState(() {
        _activeSessions.add(newSession);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Equipamento ${newSession.equipmentSerial} vinculado ao sensor ${newSession.sensorDevice.name} com sucesso!',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<bool> _ensureBluetoothPermissions() async {
    try {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();
      return scanStatus.isGranted && connectStatus.isGranted;
    } catch (_) {
      return true;
    }
  }

  void _openSessionDetail(TestSession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionLiveScreen(
          session: session,
          onSessionFinished: () {
            setState(() {
              _activeSessions.removeWhere((s) => s.id == session.id);
            });
            _loadLocalCount();
          },
        ),
      ),
    );
  }

  Future<void> _finishSession(TestSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Ensaio e Gerar Laudo?'),
        content: Text(
          'Deseja concluir o ensaio pull-down da geladeira ${session.equipmentSerial} (${session.equipmentModel})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar & Emitir Laudo'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = session.finishTest();
    await LocalReportStore.save(result);

    setState(() {
      _activeSessions.removeWhere((s) => s.id == session.id);
    });
    await _loadLocalCount();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TestReportScreen(result: result)),
    );
  }

  Future<void> _unlinkSession(TestSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular Equipamento?'),
        content: Text(
          'Deseja remover o equipamento ${session.equipmentSerial} da bancada de teste sem gerar laudo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      session.dispose();
      setState(() {
        _activeSessions.removeWhere((s) => s.id == session.id);
      });
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
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (reports.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Nenhum laudo salvo offline ainda.\nVincule um equipamento e execute um ensaio para registrar.',
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
                                backgroundColor: passed ? AppColors.ice : const Color(0xFFFFF3E0),
                                child: Icon(
                                  passed ? Icons.check_circle : Icons.warning_amber_rounded,
                                  color: passed ? AppColors.success : const Color(0xFFE65100),
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

  Color _tempColor(double temp, TestProfile profile) {
    if (temp <= profile.targetTemperature) return AppColors.success;
    if (temp <= profile.maxTemperature) return AppColors.ocean;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ISO Test • Bancada'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StandardsGuideScreen()),
              );
            },
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Guia de Normas & Ensaios',
          ),
          TextButton.icon(
            onPressed: _showSavedReportsModal,
            icon: const Icon(Icons.history, size: 20),
            label: Text(
              _localReportCount > 0 ? '$_localReportCount Laudos' : 'Histórico',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barra de Modo Operacional (Simulação vs Sensor BLE Real)
                  _buildModeSelector(),
                  const SizedBox(height: 20),

                  // Cabeçalho da Bancada Multi-Equipamento
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bancada de Qualificação Pull-Down',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _activeSessions.isEmpty
                                ? 'Nenhum equipamento em teste no momento'
                                : '${_activeSessions.length} equipamento(s) monitorado(s) em tempo real',
                            style: const TextStyle(fontSize: 13, color: AppColors.slate),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: _openLinkWizard,
                        icon: const Icon(Icons.add_link),
                        label: const Text('Vincular Equipamento'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Lista de Sessões Ativas ou Estado Vazio
                  if (_activeSessions.isEmpty)
                    _buildEmptyBench()
                  else
                    _buildActiveSessionsList(),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _activeSessions.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openLinkWizard,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar à Bancada'),
              backgroundColor: AppColors.ocean,
            )
          : null,
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(
            _useRealBle ? Icons.bluetooth_connected : Icons.science_outlined,
            color: _useRealBle ? AppColors.ocean : const Color(0xFF6366F1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _useRealBle ? 'Modo Hardware Físico (BLE AoFrio)' : 'Modo Simulação de Bancada',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.ink),
                ),
                Text(
                  _useRealBle
                      ? 'Conecta diretamente aos sensores Wellington AoFrio MON1-001.'
                      : 'Gera curvas térmicas simultâneas para validação sem hardware.',
                  style: const TextStyle(fontSize: 11, color: AppColors.slate),
                ),
              ],
            ),
          ),
          Switch(
            value: _useRealBle,
            onChanged: _toggleBleMode,
            activeColor: AppColors.ocean,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBench() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.ice,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.kitchen_outlined, size: 54, color: AppColors.ocean),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhum Equipamento Vinculado',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                'O app não se conecta automaticamente. Para iniciar a qualificação, toque no botão abaixo para escolher o sensor, identificar a geladeira e registrar o técnico responsável.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openLinkWizard,
              icon: const Icon(Icons.add_link),
              label: const Text('Vincular Primeiro Equipamento'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _activeSessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final session = _activeSessions[index];
        final tempColor = _tempColor(session.currentTemperature, session.profile);
        final target = session.profile.targetTemperature;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Topo do Card: Patrimônio, Modelo e Cronômetro
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: tempColor.withValues(alpha: 0.12),
                      radius: 22,
                      child: Icon(Icons.kitchen, color: tempColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                session.equipmentSerial,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.ice,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  session.profile.name,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ocean),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.equipmentModel,
                            style: const TextStyle(color: AppColors.slate, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // Cronômetro decorrido
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 14, color: AppColors.slate),
                          const SizedBox(width: 4),
                          Text(
                            session.elapsedFormatted,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Meio do Card: Mostrador de Temperatura e Metadados
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tempColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tempColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Temperatura Atual
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TEMPERATURA ATUAL',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.slate, letterSpacing: 0.8),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                session.currentTemperature.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  color: tempColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '°C',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tempColor),
                              ),
                            ],
                          ),
                          Text(
                            session.currentTemperature <= target
                                ? 'Estabilizando na meta'
                                : 'Em pull-down (Alvo: $target°C)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tempColor),
                          ),
                        ],
                      ),

                      // Detalhes do Sensor e Técnico
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _DetailChip(icon: Icons.sensors, text: session.sensorDevice.name),
                          const SizedBox(height: 6),
                          _DetailChip(icon: Icons.badge_outlined, text: session.technicianName),
                          const SizedBox(height: 6),
                          _DetailChip(
                            icon: session.doorOpen ? Icons.meeting_room : Icons.door_front_door,
                            text: session.doorOpen ? 'Porta Aberta' : 'Porta Fechada',
                            color: session.doorOpen ? AppColors.warning : AppColors.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Rodapé do Card: Ações (Monitorar ao vivo, Finalizar, Desvincular)
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _unlinkSession(session),
                      style: TextButton.styleFrom(foregroundColor: AppColors.slate),
                      child: const Text('Desvincular'),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _openSessionDetail(session),
                      icon: const Icon(Icons.show_chart, size: 18),
                      label: const Text('Ver Gráfico'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _finishSession(session),
                      icon: const Icon(Icons.assignment_turned_in, size: 18),
                      label: const Text('Finalizar & Laudo'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.ocean),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _DetailChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.slate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
      ],
    );
  }
}
