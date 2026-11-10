import '../models/sensor_reading.dart';

class DiscoveredDevice {
  final String id;
  final String name;
  final int rssi;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

abstract class IBleService {
  Stream<List<DiscoveredDevice>> scanForDevices();
  Future<void> stopScan();
  Future<bool> connect(String deviceId);
  Future<List<SensorReading>> downloadStoredHistory();
  Future<void> disconnect();
  bool get isConnected;
}
