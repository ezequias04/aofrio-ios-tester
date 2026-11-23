import 'diagnostic_finding.dart';
import 'sensor_reading.dart';
import 'test_profile.dart';

enum TestStatus {
  aprovada,
  reprovada,
  inconclusiva,
}

/// Laudo completo de qualificação e diagnóstico frigorífico.
class TestResult {
  final String testId;
  final String serialNumber;
  final String modelName;
  final String technicianName;
  final TestProfile profile;
  final TestStatus status;
  final String verdictReason;

  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;

  final double initialTemp;
  final double finalTemp;
  final double coolingRate; // °C por minuto
  final int doorOpenEvents;
  final double compressorDutyCycle; // 0.0 a 1.0
  final int effectiveAllowedMinutes;

  final List<SensorReading> readings;

  // Diagnóstico técnico enriquecido v2.0
  final FaultCategory faultCategory;
  final List<String> probableCauses;
  final List<String> recommendedActions;
  final String sensorId;
  final String sensorName;
  final String reportedSymptom;
  final String dataSource;
  final bool t0Validated;
  final bool isSimulated;
  final bool synced;
  final List<String> manualNotes;

  const TestResult({
    required this.testId,
    required this.serialNumber,
    required this.modelName,
    required this.technicianName,
    required this.profile,
    required this.status,
    required this.verdictReason,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.initialTemp,
    required this.finalTemp,
    required this.coolingRate,
    required this.doorOpenEvents,
    required this.compressorDutyCycle,
    required this.effectiveAllowedMinutes,
    required this.readings,
    this.faultCategory = FaultCategory.sistemaIntegro,
    this.probableCauses = const [],
    this.recommendedActions = const [],
    this.sensorId = '',
    this.sensorName = '',
    this.reportedSymptom = '',
    this.dataSource = 'BLE Ao Vivo',
    this.t0Validated = true,
    this.isSimulated = false,
    this.synced = false,
    this.manualNotes = const [],
  });

  TestResult copyWith({
    bool? synced,
    String? verdictReason,
    TestStatus? status,
  }) {
    return TestResult(
      testId: testId,
      serialNumber: serialNumber,
      modelName: modelName,
      technicianName: technicianName,
      profile: profile,
      status: status ?? this.status,
      verdictReason: verdictReason ?? this.verdictReason,
      startTime: startTime,
      endTime: endTime,
      durationMinutes: durationMinutes,
      initialTemp: initialTemp,
      finalTemp: finalTemp,
      coolingRate: coolingRate,
      doorOpenEvents: doorOpenEvents,
      compressorDutyCycle: compressorDutyCycle,
      effectiveAllowedMinutes: effectiveAllowedMinutes,
      readings: readings,
      faultCategory: faultCategory,
      probableCauses: probableCauses,
      recommendedActions: recommendedActions,
      sensorId: sensorId,
      sensorName: sensorName,
      reportedSymptom: reportedSymptom,
      dataSource: dataSource,
      t0Validated: t0Validated,
      isSimulated: isSimulated,
      synced: synced ?? this.synced,
      manualNotes: manualNotes,
    );
  }

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'serialNumber': serialNumber,
        'modelName': modelName,
        'technicianName': technicianName,
        'profileId': profile.id,
        'profileName': profile.name,
        'status': status.name.toUpperCase(),
        'verdictReason': verdictReason,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationMinutes': durationMinutes,
        'initialTemp': initialTemp,
        'finalTemp': finalTemp,
        'targetTemp': profile.targetTemperature,
        'maxAllowedMinutes': effectiveAllowedMinutes,
        'coolingRate': coolingRate,
        'doorOpenEvents': doorOpenEvents,
        'compressorDutyCycle': compressorDutyCycle,
        'faultCategory': faultCategory.name,
        'probableCauses': probableCauses,
        'recommendedActions': recommendedActions,
        'sensorId': sensorId,
        'sensorName': sensorName,
        'reportedSymptom': reportedSymptom,
        'dataSource': dataSource,
        't0Validated': t0Validated,
        'isSimulated': isSimulated,
        'synced': synced,
        'manualNotes': manualNotes,
        'readings': readings.map((r) => r.toJson()).toList(),
      };

  factory TestResult.fromJson(Map<String, dynamic> json) {
    TestStatus parseStatus(dynamic s) {
      final str = s?.toString().toLowerCase() ?? '';
      if (str.contains('aprovad')) return TestStatus.aprovada;
      if (str.contains('reprovad')) return TestStatus.reprovada;
      return TestStatus.inconclusiva;
    }

    final rawReadings = json['readings'] as List<dynamic>? ?? [];
    final parsedReadings = rawReadings.map((r) {
      if (r is Map<String, dynamic>) {
        return SensorReading.fromJson(r);
      }
      return SensorReading(
        timestamp: DateTime.now(),
        temperature: 0.0,
        doorOpen: false,
      );
    }).toList();

    return TestResult(
      testId: json['testId']?.toString() ??
          'TEST-${DateTime.now().millisecondsSinceEpoch}',
      serialNumber: json['serialNumber']?.toString() ?? 'N/D',
      modelName: json['modelName']?.toString() ?? 'Equipamento Comercial',
      technicianName: json['technicianName']?.toString() ?? 'Técnico de Campo',
      profile: TestProfile.byId(json['profileId']?.toString()),
      status: parseStatus(json['status']),
      verdictReason: json['verdictReason']?.toString() ?? 'Ensaio registrado.',
      startTime: DateTime.tryParse(json['startTime']?.toString() ?? '') ??
          DateTime.now(),
      endTime: DateTime.tryParse(json['endTime']?.toString() ?? '') ??
          DateTime.now(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      initialTemp: (json['initialTemp'] as num?)?.toDouble() ?? 25.0,
      finalTemp: (json['finalTemp'] as num?)?.toDouble() ?? 3.5,
      coolingRate: (json['coolingRate'] as num?)?.toDouble() ?? 0.35,
      doorOpenEvents: (json['doorOpenEvents'] as num?)?.toInt() ?? 0,
      compressorDutyCycle:
          (json['compressorDutyCycle'] as num?)?.toDouble() ?? 1.0,
      effectiveAllowedMinutes:
          (json['maxAllowedMinutes'] as num?)?.toInt() ?? 150,
      readings: parsedReadings,
      faultCategory:
          FaultCategoryInfo.fromString(json['faultCategory']?.toString()),
      probableCauses: (json['probableCauses'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      recommendedActions:
          (json['recommendedActions'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      sensorId: json['sensorId']?.toString() ?? '',
      sensorName: json['sensorName']?.toString() ?? '',
      reportedSymptom: json['reportedSymptom']?.toString() ?? '',
      dataSource: json['dataSource']?.toString() ?? 'BLE Ao Vivo',
      t0Validated: json['t0Validated'] != false,
      isSimulated: json['isSimulated'] == true,
      synced: json['synced'] == true,
      manualNotes: (json['manualNotes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
