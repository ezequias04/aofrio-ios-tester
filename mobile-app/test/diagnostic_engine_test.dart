import 'package:aofrio_test_app/engine/diagnostic_engine.dart';
import 'package:aofrio_test_app/models/bench_session.dart';
import 'package:aofrio_test_app/models/diagnostic_finding.dart';
import 'package:aofrio_test_app/models/sensor_reading.dart';
import 'package:aofrio_test_app/models/test_profile.dart';
import 'package:aofrio_test_app/models/test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cocaProfile = TestProfile.defaultProfiles.firstWhere(
    (p) => p.id == 'coca_cola_positive',
  );
  final beerProfile = TestProfile.defaultProfiles.firstWhere(
    (p) => p.id == 'beer_cooler_subzero',
  );

  test('diagnostica falha de partida aos 15 min com causas e checklist', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    final readings = List.generate(
      20,
      (m) => SensorReading(timestamp: t0.add(Duration(minutes: m)), temperature: 26.0 - m * 0.04),
    );

    final result = DiagnosticEngine.diagnose(
      serialNumber: 'BR-001',
      modelName: 'VB43',
      technicianName: 'Pereira',
      profile: cocaProfile,
      readings: readings,
      reportedSymptom: 'Compressor não arma',
    );

    expect(result.status, TestStatus.reprovada);
    expect(result.faultCategory, FaultCategory.falhaPartidaCompressor);
    expect(result.probableCauses, isNotEmpty);
    expect(result.recommendedActions, isNotEmpty);
    expect(result.verdictReason, contains('resposta lenta'));
  });

  test('diagnostica estagnação/reaquecimento por evaporador ou vedação', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    final readings = <SensorReading>[];
    // Cai bem nos primeiros 25 min até 16°C, depois volta a subir para 19.5°C
    for (int m = 0; m <= 50; m++) {
      final temp = m <= 25 ? (26.0 - m * 0.4) : (16.0 + (m - 25) * 0.14);
      readings.add(SensorReading(timestamp: t0.add(Duration(minutes: m)), temperature: temp));
    }

    final result = DiagnosticEngine.diagnose(
      serialNumber: 'BR-002',
      modelName: 'VN28',
      technicianName: 'Pereira',
      profile: cocaProfile,
      readings: readings,
    );

    expect(result.status, TestStatus.reprovada);
    expect(result.faultCategory, FaultCategory.estagnacaoEvaporadorPorta);
    expect(result.probableCauses.join(' '), contains('evaporador'));
  });

  test('diagnostica congelamento indevido abaixo do limite de segurança', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    final readings = <SensorReading>[];
    for (int m = 0; m <= 90; m += 2) {
      readings.add(SensorReading(
        timestamp: t0.add(Duration(minutes: m)),
        temperature: (25.0 - m * 0.35).clamp(-6.5, 25.0),
      ));
    }

    final result = DiagnosticEngine.diagnose(
      serialNumber: 'BR-003',
      modelName: 'Cervejeira 400L',
      technicianName: 'Pereira',
      profile: beerProfile,
      readings: readings,
    );

    expect(result.status, TestStatus.reprovada);
    expect(result.faultCategory, FaultCategory.falhaCorteCongelamento);
    expect(result.verdictReason, contains('CONGELAMENTO'));
  });

  test('retorna inconclusiva quando ensaio parcial saudável é encerrado cedo', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    // 25 minutos caindo forte a 0.35 °C/min (ainda em 17.25 °C)
    final readings = List.generate(
      26,
      (m) => SensorReading(timestamp: t0.add(Duration(minutes: m)), temperature: 26.0 - m * 0.35),
    );

    final result = DiagnosticEngine.diagnose(
      serialNumber: 'BR-004',
      modelName: 'VB43',
      technicianName: 'Pereira',
      profile: cocaProfile,
      readings: readings,
      allowPartial: true,
    );

    expect(result.status, TestStatus.inconclusiva);
    expect(result.faultCategory, FaultCategory.ensaioInterrompido);
  });

  test('evaluateLive calcula taxa, progresso e fase corretamente', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    final readings = List.generate(
      31,
      (m) => SensorReading(timestamp: t0.add(Duration(minutes: m)), temperature: 26.0 - m * 0.3),
    );

    final snap = DiagnosticEngine.evaluateLive(
      profile: cocaProfile,
      readings: readings,
      startedAt: t0,
      now: t0.add(const Duration(minutes: 30)),
    );

    expect(snap.phase, DiagnosticPhase.emResfriamento);
    expect(snap.health, LiveHealth.excelente);
    expect(snap.recentCoolingRate, closeTo(0.3, 0.05));
    expect(snap.t0Validated, isTrue);
    expect(snap.progressRatio, greaterThan(0.35));
    expect(snap.estimatedMinutesToTarget, isNotNull);
  });

  test('BenchSession e TestResult preservam dados completos em JSON', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    final session = BenchSession(
      id: 'SES-1',
      sensorId: 'AA:BB:CC:DD',
      sensorName: 'B15-01',
      serialNumber: 'EQ-777',
      modelName: 'VB43',
      technicianName: 'Carlos',
      profile: beerProfile,
      reportedSymptom: 'Congelando garrafas',
      startedAt: t0,
      readings: [SensorReading(timestamp: t0, temperature: 24.5)],
      manualNotes: [BenchNote(timestamp: t0, text: 'Porta verificada', isDoorEvent: true)],
      isSimulated: false,
      dataSource: 'BLE + Memória Flash SCS',
    );

    final restoredSession = BenchSession.fromJson(session.toJson());
    expect(restoredSession.profile.id, 'beer_cooler_subzero');
    expect(restoredSession.reportedSymptom, 'Congelando garrafas');
    expect(restoredSession.manualNotes.single.isDoorEvent, isTrue);

    final result = TestResult(
      testId: 'TEST-99',
      serialNumber: 'EQ-777',
      modelName: 'VB43',
      technicianName: 'Carlos',
      profile: beerProfile,
      status: TestStatus.reprovada,
      verdictReason: 'Teste',
      startTime: t0,
      endTime: t0.add(const Duration(minutes: 40)),
      durationMinutes: 40,
      initialTemp: 24.5,
      finalTemp: -6.0,
      coolingRate: 0.76,
      doorOpenEvents: 1,
      compressorDutyCycle: 1.0,
      effectiveAllowedMinutes: 240,
      readings: session.readings,
      faultCategory: FaultCategory.falhaCorteCongelamento,
      probableCauses: const ['Relé colado'],
      recommendedActions: const ['Trocar controlador'],
      synced: true,
    );

    final restoredResult = TestResult.fromJson(result.toJson());
    expect(restoredResult.profile.id, 'beer_cooler_subzero');
    expect(restoredResult.faultCategory, FaultCategory.falhaCorteCongelamento);
    expect(restoredResult.probableCauses, ['Relé colado']);
    expect(restoredResult.synced, isTrue);
  });
  test('laudo parcial exige 8 leituras e 20 min de registro', () {
    final t0 = DateTime(2026, 11, 20, 10, 0);
    List<SensorReading> serie(int n, int passoMin) => List.generate(
          n,
          (m) => SensorReading(timestamp: t0.add(Duration(minutes: m * passoMin)), temperature: 26.0 - m * 0.3),
        );
    expect(DiagnosticEngine.insufficientPartialData(serie(2, 30)), isNotNull);
    expect(DiagnosticEngine.insufficientPartialData(serie(10, 1)), isNotNull);
    expect(DiagnosticEngine.insufficientPartialData(serie(10, 3)), isNull);
    expect(
      () => DiagnosticEngine.diagnose(
        serialNumber: 'BR-009',
        modelName: 'X',
        technicianName: 'Pereira • Mat. 1',
        profile: cocaProfile,
        readings: serie(2, 30),
        allowPartial: true,
      ),
      throwsArgumentError,
    );
  });
}
