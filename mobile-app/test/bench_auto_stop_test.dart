import 'package:flutter_test/flutter_test.dart';

import 'package:aofrio_test_app/models/bench_session.dart';
import 'package:aofrio_test_app/models/sensor_reading.dart';
import 'package:aofrio_test_app/models/test_profile.dart';
import 'package:aofrio_test_app/state/bench_controller.dart';

BenchSession session({
  required DateTime start,
  required List<double> temps,
  DateTime? targetReachedAt,
  TestProfile? profile,
}) {
  return BenchSession(
    id: 'S1',
    sensorId: 'dev',
    sensorName: 'GEUB',
    serialNumber: 'X1',
    modelName: 'VB43',
    technicianName: 'Tec',
    profile: profile ?? TestProfile.defaultProfiles.first, // +3 °C, máx 180 min
    startedAt: start,
    readings: [
      for (var i = 0; i < temps.length; i++)
        SensorReading(
          timestamp: start.add(Duration(minutes: i)),
          temperature: temps[i],
        ),
    ],
    targetReachedAt: targetReachedAt,
  );
}

void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  test('não para com poucas leituras', () {
    final s = session(start: t0, temps: [25, 24, 23]);
    expect(BenchController.autoStopReasonFor(s, t0.add(const Duration(hours: 9))), isNull);
  });

  test('segue rodando enquanto não atingiu a meta nem estourou o prazo', () {
    final s = session(start: t0, temps: [25, 24, 23, 22, 21, 20]);
    expect(BenchController.autoStopReasonFor(s, t0.add(const Duration(minutes: 30))), isNull);
  });

  test('para após a meta mantida e estabilizada por 45s', () {
    final reached = t0.add(const Duration(minutes: 40));
    final s = session(
      start: t0,
      temps: [25, 20, 15, 10, 5, 3, 2.8],
      targetReachedAt: reached,
    );
    expect(BenchController.autoStopReasonFor(s, reached.add(const Duration(seconds: 30))), isNull);
    expect(
      BenchController.autoStopReasonFor(s, reached.add(const Duration(seconds: 45))),
      contains('meta'),
    );
  });

  test('para ao esgotar o tempo máximo do perfil (180 min)', () {
    final s = session(start: t0, temps: [25, 24.9, 24.8, 24.8, 24.7, 24.7]);
    expect(BenchController.autoStopReasonFor(s, t0.add(const Duration(minutes: 179))), isNull);
    expect(
      BenchController.autoStopReasonFor(s, t0.add(const Duration(minutes: 180))),
      contains('tempo máximo'),
    );
  });

  test('para na hora se congelar abaixo do limite de segurança', () {
    final s = session(start: t0, temps: [25, 10, 2, 0, -1.0, -2.0]); // limite 0 °C
    expect(
      BenchController.autoStopReasonFor(s, t0.add(const Duration(minutes: 10))),
      contains('segurança'),
    );
  });

  test('para por estagnação térmica se a temperatura estabilizar acima da meta', () {
    final s = session(
      start: t0,
      temps: [25, 20, 16, 12, 10, 8, 8.0, 8.05, 8.0, 7.95, 8.0],
    );
    expect(
      BenchController.autoStopReasonFor(s, t0.add(const Duration(minutes: 16))),
      contains('estagnação'),
    );
  });
}
