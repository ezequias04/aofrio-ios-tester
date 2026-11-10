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
    'maxAllowedMinutes': profile.maxAllowedMinutes,
    'coolingRate': coolingRate,
    'doorOpenEvents': doorOpenEvents,
    'compressorDutyCycle': compressorDutyCycle,
    'readings': readings.map((r) => r.toJson()).toList(),
  };
}
