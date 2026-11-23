import 'sensor_reading.dart';
import 'test_profile.dart';

/// Nota manual registrada pelo técnico durante um ensaio na bancada (ex: troca de termostato, porta aberta).
class BenchNote {
  final DateTime timestamp;
  final String text;
  final bool isDoorEvent;

  const BenchNote({
    required this.timestamp,
    required this.text,
    this.isDoorEvent = false,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'text': text,
        'isDoorEvent': isDoorEvent,
      };

  factory BenchNote.fromJson(Map<String, dynamic> json) => BenchNote(
        timestamp:
            DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
                DateTime.now(),
        text: json['text']?.toString() ?? '',
        isDoorEvent: json['isDoorEvent'] == true,
      );
}

/// Sessão ativa de diagnóstico multicanal na bancada (persistida em SharedPreferences).
class BenchSession {
  final String id;
  final String sensorId;
  final String sensorName;
  final String serialNumber;
  final String modelName;
  final String technicianName;
  final TestProfile profile;
  final String reportedSymptom;
  final DateTime startedAt;
  final List<SensorReading> readings;
  final List<BenchNote> manualNotes;
  final bool isSimulated;
  final String dataSource;
  final DateTime? lastSeenAt;
  final int? lastRssi;
  final DateTime? targetReachedAt;

  const BenchSession({
    required this.id,
    required this.sensorId,
    required this.sensorName,
    required this.serialNumber,
    required this.modelName,
    required this.technicianName,
    required this.profile,
    this.reportedSymptom = '',
    required this.startedAt,
    required this.readings,
    this.manualNotes = const [],
    this.isSimulated = false,
    this.dataSource = 'BLE Ao Vivo',
    this.lastSeenAt,
    this.lastRssi,
    this.targetReachedAt,
  });

  double? get latestTemp => readings.isEmpty ? null : readings.last.temperature;

  double? get initialTemp =>
      readings.isEmpty ? null : readings.first.temperature;

  Duration elapsed([DateTime? now]) =>
      (now ?? DateTime.now()).difference(startedAt);

  bool isSignalStale([
    Duration threshold = const Duration(seconds: 20),
    DateTime? now,
  ]) {
    if (lastSeenAt == null) return true;
    return (now ?? DateTime.now()).difference(lastSeenAt!) >= threshold;
  }

  BenchSession copyWith({
    String? sensorName,
    String? serialNumber,
    String? modelName,
    String? technicianName,
    TestProfile? profile,
    String? reportedSymptom,
    List<SensorReading>? readings,
    List<BenchNote>? manualNotes,
    String? dataSource,
    DateTime? lastSeenAt,
    int? lastRssi,
    DateTime? targetReachedAt,
  }) {
    return BenchSession(
      id: id,
      sensorId: sensorId,
      sensorName: sensorName ?? this.sensorName,
      serialNumber: serialNumber ?? this.serialNumber,
      modelName: modelName ?? this.modelName,
      technicianName: technicianName ?? this.technicianName,
      profile: profile ?? this.profile,
      reportedSymptom: reportedSymptom ?? this.reportedSymptom,
      startedAt: startedAt,
      readings: readings ?? this.readings,
      manualNotes: manualNotes ?? this.manualNotes,
      isSimulated: isSimulated,
      dataSource: dataSource ?? this.dataSource,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastRssi: lastRssi ?? this.lastRssi,
      targetReachedAt: targetReachedAt ?? this.targetReachedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sensorId': sensorId,
        'sensorName': sensorName,
        'serialNumber': serialNumber,
        'modelName': modelName,
        'technicianName': technicianName,
        'profileId': profile.id,
        'reportedSymptom': reportedSymptom,
        'startedAt': startedAt.toIso8601String(),
        'readings': readings.map((r) => r.toJson()).toList(),
        'manualNotes': manualNotes.map((n) => n.toJson()).toList(),
        'isSimulated': isSimulated,
        'dataSource': dataSource,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'lastRssi': lastRssi,
        'targetReachedAt': targetReachedAt?.toIso8601String(),
      };

  factory BenchSession.fromJson(Map<String, dynamic> json) {
    final rawReadings = json['readings'] as List<dynamic>? ?? const [];
    final rawNotes = json['manualNotes'] as List<dynamic>? ?? const [];
    return BenchSession(
      id: json['id']?.toString() ??
          'SES-${DateTime.now().millisecondsSinceEpoch}',
      sensorId: json['sensorId']?.toString() ?? '',
      sensorName: json['sensorName']?.toString() ?? '',
      serialNumber: json['serialNumber']?.toString() ?? 'N/D',
      modelName: json['modelName']?.toString() ?? 'Refrigerador',
      technicianName: json['technicianName']?.toString() ?? 'Técnico',
      profile: TestProfile.byId(json['profileId']?.toString()),
      reportedSymptom: json['reportedSymptom']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      readings: rawReadings
          .whereType<Map<String, dynamic>>()
          .map(SensorReading.fromJson)
          .toList(),
      manualNotes: rawNotes
          .whereType<Map<String, dynamic>>()
          .map(BenchNote.fromJson)
          .toList(),
      isSimulated: json['isSimulated'] == true,
      dataSource: json['dataSource']?.toString() ?? 'BLE Ao Vivo',
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'].toString())
          : null,
      lastRssi: (json['lastRssi'] as num?)?.toInt(),
      targetReachedAt: json['targetReachedAt'] != null
          ? DateTime.tryParse(json['targetReachedAt'].toString())
          : null,
    );
  }
}
