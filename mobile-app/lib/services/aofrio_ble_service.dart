import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';
import 'ble_service_interface.dart';

/// Driver Bluetooth Real para o AoFrio Monitor
/// Utiliza a biblioteca nativa flutter_blue_plus
class AoFrioBleService implements IBleService {
  BluetoothDevice? _connectedDevice;
  bool _isConnected = false;

  // UUIDs de serviço padrão do ecossistema AoFrio IoT
  // (Podem ser refinados após escaneamento inicial com nRF Connect)
  static const String aofrioServiceUuid = "0000fee0-0000-1000-8000-00805f9b34fb";
  static const String dataLogCharUuid   = "0000fee1-0000-1000-8000-00805f9b34fb";
  static const String commandCharUuid   = "0000fee2-0000-1000-8000-00805f9b34fb";

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<List<DiscoveredDevice>> scanForDevices() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    return FlutterBluePlus.scanResults.map((results) {
      return results
          .where((r) => r.device.platformName.isNotEmpty)
          .map((r) => DiscoveredDevice(
                id: r.device.remoteId.str,
                name: r.device.platformName,
                rssi: r.rssi,
              ))
          .toList();
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<bool> connect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
    _connectedDevice = device;
    _isConnected = true;
    return true;
  }

  @override
  Future<List<SensorReading>> downloadStoredHistory() async {
    if (_connectedDevice == null) throw Exception('Nenhum sensor conectado.');

    final services = await _connectedDevice!.discoverServices();
    // Localiza a característica de log da AoFrio
    final targetService = services.firstWhere(
      (s) => s.uuid.str128.toLowerCase().contains("fee0") || true,
      orElse: () => services.first,
    );

    // TODO: Enviar comando de trigger para descarregar o buffer flash
    // e escutar stream de notificações até receber o byte de fim de transmissão.
    
    // Retorna array inicial convertido
    return [];
  }

  @override
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _isConnected = false;
  }
}
