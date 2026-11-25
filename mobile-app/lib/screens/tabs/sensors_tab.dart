import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../services/wellington_ble_service.dart';
import '../../theme/app_theme.dart';
import '../diagnostic_live_screen.dart';
import '../flash_log_screen.dart';

class SensorsTab extends StatefulWidget {
  final ValueChanged<String> onBindSensor;
  final VoidCallback onOpenBench;

  const SensorsTab({
    super.key,
    required this.onBindSensor,
    required this.onOpenBench,
  });

  @override
  State<SensorsTab> createState() => _SensorsTabState();
}

class _SensorsTabState extends State<SensorsTab> {
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final sensors = controller.discoveredSensors;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar de Sensores'),
        actions: [
          IconButton(
            tooltip: 'Reiniciar busca BLE',
            onPressed: controller.isDownloadingFlash
                ? null
                : () => controller.startRadar(restart: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    controller.scanning
                        ? Icons.bluetooth_searching_rounded
                        : Icons.bluetooth_rounded,
                    color: AppColors.cryoBright,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.demoModeEnabled
                              ? 'Simulação ativa (${sensors.length} sensores)'
                              : (controller.scanning
                                  ? '${sensors.length} sensor(es) por perto'
                                  : 'Busca de sensores parada'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Toque em Testar no sensor da geladeira.',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isAndroid) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.indigoSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.nfc_rounded, size: 18, color: AppColors.indigo),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Android: Use o Radar BLE abaixo ou o leitor de QR Code no patrimônio ao vincular.',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (controller.bleError != null && !controller.demoModeEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.faultBg,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.fault.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.fault),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.bleError!,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => controller.startRadar(restart: true),
                      icon: const Icon(Icons.bluetooth_searching_rounded),
                      label: const Text('Tentar Novamente'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (sensors.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.sensors_off_rounded,
                        size: 46,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhum sensor AoFrio / Wellington detectado',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Aproxime o telefone a menos de 5 metros do sensor MON1-001 ou ative o Simulador de Bancada na aba Normas para testar sem hardware.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.slate, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => controller.startRadar(restart: true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Procurar Novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sensors.map((sensor) {
                final age = now.difference(sensor.at);
                final linked = controller.activeSessionForSensor(sensor.deviceId);
                final isSim = sensor.deviceId.startsWith('SIM-');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SensorTileCard(
                    sensor: sensor,
                    age: age,
                    isSim: isSim,
                    linkedSerial: linked?.serialNumber,
                    onBind: () {
                      if (linked != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DiagnosticLiveScreen(sessionId: linked.id),
                          ),
                        );
                      } else {
                        widget.onBindSensor(sensor.deviceId);
                      }
                    },
                    onReadFlash: isSim
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FlashLogScreen(
                                  sensorId: sensor.deviceId,
                                  sensorName: sensor.assetName,
                                ),
                              ),
                            );
                          },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SensorTileCard extends StatelessWidget {
  final LiveTelemetry sensor;
  final Duration age;
  final bool isSim;
  final String? linkedSerial;
  final VoidCallback onBind;
  final VoidCallback? onReadFlash;

  const _SensorTileCard({
    required this.sensor,
    required this.age,
    required this.isSim,
    required this.linkedSerial,
    required this.onBind,
    required this.onReadFlash,
  });

  @override
  Widget build(BuildContext context) {
    final stale = !isSim && age.inSeconds >= 15;
    final temp = sensor.temperatureC;
    final tempColor = stale
        ? AppColors.muted
        : (temp != null && temp <= 4.0 ? AppColors.cryo : AppColors.ink);

    return Opacity(
      opacity: stale ? 0.6 : 1.0,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSim ? AppColors.warningBg : AppColors.cryoSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSim ? Icons.science_rounded : Icons.sensors_rounded,
                      color: isSim ? AppColors.warning : AppColors.cryo,
                    ),
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
                                sensor.assetName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            if (isSim) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'SIMULADO',
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
                        Text(
                          // Sem o identificador técnico (UUID): só o que o técnico usa.
                          'Sinal ${sensor.rssi >= -65 ? 'forte' : (sensor.rssi >= -80 ? 'médio' : 'fraco')} • ${stale ? 'atualizado há ${age.inSeconds}s' : 'ao vivo'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.slate, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        temp == null ? 'aguardando' : '${temp.toStringAsFixed(1)}°C',
                        style: TextStyle(
                          fontSize: temp == null ? 14 : 24,
                          fontWeight: FontWeight.w900,
                          color: tempColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (linkedSerial != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.indigoSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Vinculado em ensaio ativo: $linkedSerial',
                    style: const TextStyle(
                      color: AppColors.indigo,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onBind,
                      icon: Icon(
                        linkedSerial != null
                            ? Icons.open_in_new_rounded
                            : Icons.add_link_rounded,
                        size: 18,
                      ),
                      label: Text(
                        linkedSerial != null
                            ? 'Ver ensaio'
                            : 'Testar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (onReadFlash != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReadFlash,
                        icon: const Icon(Icons.memory_rounded, size: 18),
                        label: const Text('Memória', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
