import 'dart:async';
import 'package:flutter/material.dart';
import '../services/wellington_ble_service.dart';
import '../theme/app_theme.dart';

/// Monitor em tempo real: lê a temperatura que o sensor Wellington/AoFrio
/// transmite no anúncio BLE, sem conexão e sem autenticação. Trava no sensor
/// de maior sinal e atualiza a cada anúncio novo.
class LiveMonitorScreen extends StatefulWidget {
  final WellingtonBleService service;
  const LiveMonitorScreen({super.key, required this.service});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  late final Stream<LiveTelemetry> _stream;

  @override
  void initState() {
    super.initState();
    // Stream único (broadcast implícito pelo StreamBuilder); ao sair da tela
    // o cancelamento fecha o scan via finally do watchLiveTelemetry.
    _stream = widget.service.watchLiveTelemetry();
  }

  @override
  void dispose() {
    widget.service.stopScan();
    super.dispose();
  }

  Color _tempColor(double? t) {
    if (t == null) return AppColors.slate;
    if (t <= 5) return AppColors.success; // faixa fria normal de expositor
    if (t <= 10) return AppColors.ocean;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Temperatura em tempo real')),
      body: SafeArea(
        child: StreamBuilder<LiveTelemetry>(
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
                text: 'Procurando o sensor…\nAproxime o aparelho do refrigerador.',
                showSpinner: true,
              );
            }
            final t = snap.data!;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (t.assetName.isNotEmpty)
                      Text(t.assetName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 18),
                    _TempDial(temp: t.temperatureC, color: _tempColor(t.temperatureC)),
                    const SizedBox(height: 8),
                    _LiveDot(at: t.at),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(child: _Stat(label: 'Sinal', value: '${t.rssi} dBm', icon: Icons.wifi)),
                      const SizedBox(width: 12),
                      Expanded(child: _DoorCard(flagBytes: t.flagBytes)),
                    ]),
                    const SizedBox(height: 16),
                    _RawCard(hex: t.rawHex),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TempDial extends StatelessWidget {
  final double? temp;
  final Color color;
  const _TempDial({required this.temp, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 2),
      ),
      child: Column(children: [
        Text(
          temp == null ? '—' : temp!.toStringAsFixed(1),
          style: TextStyle(fontSize: 88, height: 1, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 4),
        Text('°C',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _LiveDot extends StatelessWidget {
  final DateTime at;
  const _LiveDot({required this.at});
  @override
  Widget build(BuildContext context) {
    final hhmmss = at.toIso8601String().substring(11, 19);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
      const SizedBox(width: 7),
      Text('ao vivo • atualizado $hhmmss', style: const TextStyle(color: AppColors.slate, fontSize: 12)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.ocean, size: 20),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        ]),
      );
}

/// Porta: o bit de "porta aberta" ainda não foi confirmado neste payload.
/// Mostra os bytes de flag em binário pra identificar no hardware qual muda
/// ao abrir a porta. Nunca afirma um estado que não foi comprovado.
class _DoorCard extends StatelessWidget {
  final List<int> flagBytes;
  const _DoorCard({required this.flagBytes});
  @override
  Widget build(BuildContext context) {
    final bits = flagBytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join(' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.sensor_door_outlined, color: AppColors.ocean, size: 20),
        const SizedBox(height: 8),
        const Text('Flags (porta?)', style: TextStyle(color: AppColors.slate, fontSize: 12)),
        const SizedBox(height: 2),
        Text(bits, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('abra a porta e veja qual bit muda',
            style: TextStyle(color: AppColors.slate, fontSize: 10)),
      ]),
    );
  }
}

class _RawCard extends StatelessWidget {
  final String hex;
  const _RawCard({required this.hex});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Anúncio bruto (0x578)', style: TextStyle(color: AppColors.slate, fontSize: 11)),
          const SizedBox(height: 4),
          SelectableText(hex, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.ink)),
        ]),
      );
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
