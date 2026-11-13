import 'dart:async';
import 'dart:math';
import '../engine/pull_down_analyzer.dart';
import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../services/ble_service_interface.dart';

enum SessionStatus {
  emAndamento,
  estabilizando,
  concluidoAprovado,
  concluidoReprovado,
}

class TestSession {
  final String id;
  final String equipmentSerial; // Patrimônio do equipamento em teste
  final String equipmentModel;  // Modelo da geladeira
  final String technicianName;  // Responsável pelo teste
  final TestProfile profile;    // Perfil ISO 23953
  final DiscoveredDevice sensorDevice; // Dispositivo AoFrio vinculado
  final DateTime startTime;
  final Duration targetDuration;
  final List<SensorReading> readings;

  double currentTemperature;
  bool doorOpen;
  bool compressorOn;
  SessionStatus status;
  Timer? updateTimer;
  IBleService? bleService;

  TestSession({
    required this.id,
    required this.equipmentSerial,
    required this.equipmentModel,
    required this.technicianName,
    required this.profile,
    required this.sensorDevice,
    required this.startTime,
    required this.targetDuration,
    List<SensorReading>? initialReadings,
    this.currentTemperature = 24.5,
    this.doorOpen = false,
    this.compressorOn = true,
    this.status = SessionStatus.emAndamento,
    this.bleService,
  }) : readings = initialReadings ?? [];

  Duration get elapsedTime => DateTime.now().difference(startTime);

  String get elapsedFormatted {
    final d = elapsedTime;
    final hours = d.inHours.toString().padLeft(2, '0');
    final mins = (d.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$mins:$secs';
  }

  void addReading(double temp, {bool isDoorOpen = false, bool isCompOn = true}) {
    currentTemperature = temp;
    doorOpen = isDoorOpen;
    compressorOn = isCompOn;
    readings.add(SensorReading(
      timestamp: DateTime.now(),
      temperature: temp,
      doorOpen: isDoorOpen,
      compressorOn: isCompOn,
    ));

    // Atualiza status baseado no setpoint do perfil
    if (temp <= profile.targetTemperature) {
      status = SessionStatus.estabilizando;
    }
  }

  TestResult finishTest() {
    updateTimer?.cancel();
    updateTimer = null;

    final readingsToAnalyze = readings.isEmpty
        ? [
            SensorReading(
              timestamp: startTime,
              temperature: currentTemperature,
              doorOpen: doorOpen,
              compressorOn: compressorOn,
            )
          ]
        : readings;

    return PullDownAnalyzer.analyze(
      serialNumber: equipmentSerial,
      modelName: equipmentModel,
      technicianName: technicianName,
      profile: profile,
      readings: readingsToAnalyze,
    );
  }

  void dispose() {
    updateTimer?.cancel();
    updateTimer = null;
  }
}
