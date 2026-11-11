import 'sensor_reading.dart';
import 'test_profile.dart';

enum TestStatus {
  aprovada,
  reprovada,
  inconclusiva,
}

/// Laudo final gerado pelo algoritmo de pull-down
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
  final double compressorDutyCycle; // 0.0 a 1.0 (100%)
  final int effectiveAllowedMinutes;
  
  final List<SensorReading> readings;

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
  });

  Map<String, dynamic> toJson() => {
    'testId': testId,
    'serialNumber': serialNumber,
    'modelName': modelName,
    'technicianName': technicianName,
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
      testId: json['testId']?.toString() ?? 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      serialNumber: json['serialNumber']?.toString() ?? 'N/D',
      modelName: json['modelName']?.toString() ?? 'Equipamento Comercial',
      technicianName: json['technicianName']?.toString() ?? 'Técnico de Campo',
      profile: TestProfile.defaultProfiles.first,
      status: parseStatus(json['status']),
      verdictReason: json['verdictReason']?.toString() ?? 'Ensaio registrado.',
      startTime: DateTime.tryParse(json['startTime']?.toString() ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime']?.toString() ?? '') ?? DateTime.now(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      initialTemp: (json['initialTemp'] as num?)?.toDouble() ?? 25.0,
      finalTemp: (json['finalTemp'] as num?)?.toDouble() ?? 3.5,
      coolingRate: (json['coolingRate'] as num?)?.toDouble() ?? 0.35,
      doorOpenEvents: (json['doorOpenEvents'] as num?)?.toInt() ?? 0,
      compressorDutyCycle: (json['compressorDutyCycle'] as num?)?.toDouble() ?? 1.0,
      effectiveAllowedMinutes: (json['maxAllowedMinutes'] as num?)?.toInt() ?? 150,
      readings: parsedReadings,
    );
  }
}
