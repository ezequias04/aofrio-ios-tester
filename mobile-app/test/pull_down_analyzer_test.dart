import 'package:aofrio_test_app/engine/pull_down_analyzer.dart';
import 'package:aofrio_test_app/models/sensor_reading.dart';
import 'package:aofrio_test_app/models/test_profile.dart';
import 'package:aofrio_test_app/models/test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = TestProfile(
    id: 'test',
    name: 'Perfil de teste',
    standardName: 'Padrão de teste',
    targetTemperature: 4,
    manualMaxAllowedMinutes: 90,
  );

  List<SensorReading> readings({required double dropPerMinute}) {
    final start = DateTime(2026, 11, 9, 8);
    return List.generate(121, (minute) => SensorReading(
      timestamp: start.add(Duration(minutes: minute)),
      temperature: 26 - (dropPerMinute * minute),
      compressorOn: true,
    ));
  }

  test('aprova quando alcança o setpoint dentro do limite', () {
    final result = PullDownAnalyzer.analyze(
      serialNumber: 'EQ-001',
      modelName: 'Expositor',
      technicianName: 'Técnico',
      profile: profile,
      readings: readings(dropPerMinute: .3),
    );

    expect(result.status, TestStatus.aprovada);
    expect(result.durationMinutes, lessThanOrEqualTo(90));
    expect(result.toJson()['maxAllowedMinutes'], 90);
  });

  test('reprova quando a resposta inicial é insuficiente', () {
    final result = PullDownAnalyzer.analyze(
      serialNumber: 'EQ-002',
      modelName: 'Expositor',
      technicianName: 'Técnico',
      profile: profile,
      readings: readings(dropPerMinute: .05),
    );

    expect(result.status, TestStatus.reprovada);
    expect(result.verdictReason, contains('resposta lenta'));
  });
}
