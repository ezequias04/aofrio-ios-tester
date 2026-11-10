import 'dart:async';
import 'dart:math';
import '../models/sensor_reading.dart';
import 'ble_service_interface.dart';

enum MockScenario {
  refrigeratorPass,    // Atinge 2.5°C em ~55 min (Aprovada)
  refrigeratorFailGas, // Não atinge a meta, para em 12°C (Reprovada)
  doorViolation,       // Alguém abre a porta no meio do teste
}

/// Simulador de Sensor AoFrio para desenvolvimento e testes
/// Permite testar o app completamente antes do sensor físico chegar
class MockBleService implements IBleService {
  MockScenario currentScenario = MockScenario.refrigeratorPass;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<DiscoveredDevice>> scanForDevices() async* {
    yield [
      const DiscoveredDevice(id: 'AOFRIO-MTR-0041', name: 'AoFrio Monitor 41', rssi: -58),
      const DiscoveredDevice(id: 'AOFRIO-MTR-0089', name: 'AoFrio Monitor 89', rssi: -72),
      const DiscoveredDevice(id: 'WDRIVE-CONN-102', name: 'Connect Monitor Test', rssi: -65),
    ];
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> connect(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 1200)); // Simula handshake BLE
    _connected = true;
    return true;
  }

  @override
  Future<List<SensorReading>> downloadStoredHistory() async {
    if (!_connected) throw Exception('Não conectado ao dispositivo.');
    
    // Simula tempo de transferência da memória flash do sensor via BLE (2 segundos)
    await Future.delayed(const Duration(seconds: 2));

    final now = DateTime.now();
    final startTime = now.subtract(const Duration(hours: 3));
    final List<SensorReading> list = [];

    // Gerar leituras minuto a minuto
    double temp = 27.2; // Temp ambiente inicial
    final random = Random();

    for (int minute = 0; minute <= 140; minute++) {
      final timestamp = startTime.add(Duration(minutes: minute));
      bool doorOpen = false;
      bool compressorOn = true;

      switch (currentScenario) {
        case MockScenario.refrigeratorPass:
          // Queda exponencial realista de pull-down
          if (temp > 2.8) {
            final drop = 0.35 + (temp - 2.8) * 0.02 + (random.nextDouble() * 0.05);
            temp = max(2.6, temp - drop);
          } else {
            // Ciclo de estabilização do termostato
            temp = 2.6 + sin(minute / 5.0) * 0.4;
          }
          break;

        case MockScenario.refrigeratorFailGas:
          // Resfriamento deficiente (estagna em 12°C)
          if (temp > 12.0) {
            temp -= 0.12;
          } else {
            temp = 12.0 + sin(minute / 8.0) * 0.3;
          }
          break;

        case MockScenario.doorViolation:
          // Abertura de porta aos 30 minutos
          if (minute >= 30 && minute <= 36) {
            doorOpen = true;
            temp += 0.8; // Pico de calor entrando
          } else if (temp > 2.8) {
            temp -= 0.30;
          }
          break;
      }

      list.add(SensorReading(
        timestamp: timestamp,
        temperature: double.parse(temp.toStringAsFixed(1)),
        doorOpen: doorOpen,
        compressorOn: compressorOn,
      ));
    }

    return list;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }
}
