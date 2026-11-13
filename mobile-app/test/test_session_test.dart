import 'package:aofrio_test_app/models/test_profile.dart';
import 'package:aofrio_test_app/models/test_session.dart';
import 'package:aofrio_test_app/services/ble_service_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TestSession acumula leituras e gera TestResult corretamente', () {
    const profile = TestProfile.defaultProfiles.first;
    const device = DiscoveredDevice(id: 'AOFRIO-001', name: 'Sensor 1', rssi: -60);

    final session = TestSession(
      id: 'SESSION-1',
      equipmentSerial: 'GEL-1001',
      equipmentModel: 'Expositor 450L',
      technicianName: 'Técnico Pereira',
      profile: profile,
      sensorDevice: device,
      startTime: DateTime.now().subtract(const Duration(minutes: 40)),
      targetDuration: const Duration(minutes: 60),
    );

    expect(session.equipmentSerial, 'GEL-1001');
    expect(session.sensorDevice.name, 'Sensor 1');
    expect(session.readings.isEmpty, true);

    // Adiciona leituras
    session.addReading(18.0);
    session.addReading(10.0);
    session.addReading(3.0); // atinge target (M1 = 3.0°C)

    expect(session.readings.length, 3);
    expect(session.currentTemperature, 3.0);
    expect(session.status, SessionStatus.estabilizando);

    // Finaliza
    final result = session.finishTest();
    expect(result.serialNumber, 'GEL-1001');
    expect(result.technicianName, 'Técnico Pereira');
  });
}
