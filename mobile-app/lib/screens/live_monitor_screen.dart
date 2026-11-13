import 'package:flutter/material.dart';
import '../services/wellington_ble_service.dart';
import '../theme/app_theme.dart';

/// Monitor em tempo real: lê a temperatura que os sensores Wellington/AoFrio
/// transmitem no anúncio BLE, sem conexão e sem autenticação. Mostra TODOS os
/// sensores próximos ao mesmo tempo, cada um atualizando ao vivo. Continua
/// lendo com o app minimizado (iOS bluetooth-central / scan em background).
class LiveMonitorScreen extends StatefulWidget {
  final WellingtonBleService service;
  const LiveMonitorScreen({super.key, required this.service});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  late final Stream<List<LiveTelemetry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.service.watchAllLiveTelemetry();
  }

  @override
  void dispose() {
    widget.service.stopScan();
    super.dispose();
  }

  static Color tempColor(double? t) {
    if (t == null) return AppColors.slate;
    if (t <= 5) return AppColors.success;
    if (t <= 10) return AppColors.ocean;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensores em tempo real')),
      body: SafeArea(
        child: StreamBuilder<List<LiveTelemetry>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return _Message(
                icon: Icons.bluetooth_disabled,
                text: snap.error.toString().replaceFirst('Exception: ', ''),
              );
            }
            if (!snap.hasData) {
              return const _Message(
                icon: Icons.bluetooth_searching,
                text: 'Procurando sensores…\nAproxime o aparelho dos refrigeradores.',
                showSpinner: true,
              );
            }
            final list = snap.data!;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('${list.length} sensor${list.length == 1 ? '' : 'es'} ao vivo',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ]),
                  );
                }
                return _SensorCard(t: list[i - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final LiveTelemetry t;
  const _SensorCard({required this.t});

  @override
  Widget build(BuildContext context) {
    final color = _LiveMonitorScreenState.tempColor(t.temperatureC);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              t.assetName.isEmpty ? t.deviceId : t.assetName,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.wifi, size: 14, color: AppColors.slate),
          const SizedBox(width: 4),
          Text('${t.rssi} dBm', style: const TextStyle(color: AppColors.slate, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            t.temperatureC == null ? '—' : t.temperatureC!.toStringAsFixed(1),
            style: TextStyle(fontSize: 52, height: 1, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('°C', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          ),
          const Spacer(),
          _DoorFlags(flagBytes: t.flagBytes),
        ]),
      ]),
    );
  }
}

/// Bit de "porta aberta" ainda NÃO confirmado neste payload. Mostra os bytes
/// de flag em binário pra identificar no hardware qual muda ao abrir a porta.
class _DoorFlags extends StatelessWidget {
  final List<int> flagBytes;
  const _DoorFlags({required this.flagBytes});
  @override
  Widget build(BuildContext context) {
    final bits = flagBytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join(' ');
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.sensor_door_outlined, size: 14, color: AppColors.slate),
        SizedBox(width: 4),
        Text('porta?', style: TextStyle(color: AppColors.slate, fontSize: 11)),
      ]),
      const SizedBox(height: 2),
      Text(bits, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 12)),
    ]);
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool showSpinner;
  const _Message({required this.icon, required this.text, this.showSpinner = false});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.slate),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate)),
            if (showSpinner) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(strokeWidth: 2.6),
            ],
          ]),
        ),
      );
}
