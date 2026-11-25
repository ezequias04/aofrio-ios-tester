import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/diagnostic_engine.dart';
import '../models/bench_session.dart';
import '../models/diagnostic_finding.dart';
import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../services/active_sessions_store.dart';
import '../services/local_report_store.dart';
import '../services/wellington_ble_service.dart';

/// Controlador central do sistema ISO Test:
/// - Radar BLE passivo alimentando múltiplos ensaios simultâneos na bancada
/// - Persistência local imediata das sessões ativas (sobrevive a fechamento do app)
/// - Integração com leitura da memória flash SCS interna
/// - Modo demonstração opcional (desligado por padrão) para validar fluxos sem hardware
class BenchController extends ChangeNotifier {
  final WellingtonBleService _ble = WellingtonBleService();

  final Map<String, LiveTelemetry> _realSensors = {};
  final Map<String, LiveTelemetry> _demoSensors = {};
  List<BenchSession> _activeSessions = [];
  List<TestResult> _savedReports = [];

  StreamSubscription<List<LiveTelemetry>>? _radarSub;
  Timer? _demoTimer;

  bool _initialized = false;
  bool _scanning = false;
  bool _isDownloadingFlash = false;
  bool _demoModeEnabled = false;
  String? _bleError;
  String _lastTechnicianName = '';
  String _technicianBadge = '';
  String _technicianPin = '';

  bool get initialized => _initialized;
  bool get scanning => _scanning;
  bool get isDownloadingFlash => _isDownloadingFlash;
  bool get demoModeEnabled => _demoModeEnabled;
  String? get bleError => _bleError;
  String get lastTechnicianName => _lastTechnicianName;
  String get technicianBadge => _technicianBadge;

  /// Quem está testando: nome e matrícula informados neste aparelho.
  bool get hasIdentity =>
      _lastTechnicianName.isNotEmpty && _technicianBadge.isNotEmpty && _technicianPin.isNotEmpty;

  /// Confere o PIN de quem está identificado (assina ensaio e laudo).
  bool checkPin(String pin) => _technicianPin.isNotEmpty && pin.trim() == _technicianPin;

  /// Nome + matrícula: é o que vai gravado em todo ensaio e laudo.
  String get technicianLabel => _technicianBadge.isEmpty
      ? _lastTechnicianName
      : '$_lastTechnicianName • Mat. $_technicianBadge';

  Future<void> saveIdentity({required String name, required String badge, required String pin}) async {
    _lastTechnicianName = name.trim();
    _technicianBadge = badge.trim();
    _technicianPin = pin.trim();
    await ActiveSessionsStore.saveTechnicianPin(_technicianPin);
    await ActiveSessionsStore.saveLastTechnician(_lastTechnicianName);
    await ActiveSessionsStore.saveTechnicianBadge(_technicianBadge);
    notifyListeners();
  }

  List<BenchSession> get activeSessions => List.unmodifiable(_activeSessions);
  List<TestResult> get savedReports => List.unmodifiable(_savedReports);


  /// Lista combinada de sensores ativos (reais + simulados se modo demo ativo),
  /// em ordem fixa (nome do ativo): ordenar por sinal fazia a lista pular.
  List<LiveTelemetry> get discoveredSensors {
    final map = <String, LiveTelemetry>{..._realSensors};
    if (_demoModeEnabled) {
      map.addAll(_demoSensors);
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final c = a.assetName.compareTo(b.assetName);
        return c != 0 ? c : a.deviceId.compareTo(b.deviceId);
      });
    return list;
  }

  LiveTelemetry? telemetryForSensor(String sensorId) {
    if (_demoModeEnabled && _demoSensors.containsKey(sensorId)) {
      return _demoSensors[sensorId];
    }
    return _realSensors[sensorId];
  }

  BenchSession? activeSessionForSensor(String sensorId) {
    for (final s in _activeSessions) {
      if (s.sensorId == sensorId) return s;
    }
    return null;
  }

  BenchSession? sessionById(String sessionId) {
    for (final s in _activeSessions) {
      if (s.id == sessionId) return s;
    }
    return null;
  }

  Future<void> initialize() async {
    _activeSessions = await ActiveSessionsStore.loadSessions();
    _lastTechnicianName = await ActiveSessionsStore.loadLastTechnician();
    _technicianBadge = await ActiveSessionsStore.loadTechnicianBadge();
    _technicianPin = await ActiveSessionsStore.loadTechnicianPin();
    _demoModeEnabled = await ActiveSessionsStore.loadDemoMode();
    _savedReports = await LocalReportStore.getAll();
    _initialized = true;
    await _syncWakelock();
    if (_demoModeEnabled) {
      _startDemoTicker();
    }
    notifyListeners();
    unawaited(startRadar());
  }

  Future<void> _syncWakelock() async {
    // Busca rápida de sensores só enquanto houver ensaio rodando (bateria).
    _ble.highFrequencyScan = _activeSessions.isNotEmpty;
    try {
      if (_activeSessions.isNotEmpty) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Ignora em plataformas sem plugin ou ambiente de teste.
    }
  }

  Future<void> _ensurePermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied = statuses.values
        .any((status) => status.isDenied || status.isPermanentlyDenied);
    if (denied) {
      throw Exception(
        'Autorize Bluetooth e Dispositivos Próximos nas configurações do Android para localizar os sensores.',
      );
    }
  }

  Future<void> startRadar({bool restart = false}) async {
    if (_isDownloadingFlash) return;
    if (_radarSub != null) {
      if (!restart) return;
      await _radarSub!.cancel();
      _radarSub = null;
    }

    _bleError = null;
    _scanning = true;
    notifyListeners();

    try {
      await _ensurePermissions();
      _radarSub = _ble.watchAllLiveTelemetry().listen(
        _onTelemetryBatch,
        onError: (Object err) {
          _bleError = err.toString().replaceFirst('Exception: ', '');
          _scanning = false;
          _radarSub = null;
          notifyListeners();
        },
        onDone: () {
          _scanning = false;
          _radarSub = null;
          notifyListeners();
        },
      );
    } catch (e) {
      _bleError = e.toString().replaceFirst('Exception: ', '');
      _scanning = false;
      _radarSub = null;
      notifyListeners();
    }
  }

  void _onTelemetryBatch(List<LiveTelemetry> batch) {
    bool shouldPersist = false;

    for (final t in batch) {
      _realSensors[t.deviceId] = t;

      for (int i = 0; i < _activeSessions.length; i++) {
        final session = _activeSessions[i];
        if (session.sensorId != t.deviceId || session.isSimulated) continue;

        final prevReadings = session.readings;
        var nextReadings = prevReadings;
        var nextTargetAt = session.targetReachedAt;

        if (t.temperatureC != null) {
          final temp = t.temperatureC!;
          final last = prevReadings.isEmpty ? null : prevReadings.last;
          final changed = last == null || (temp - last.temperature).abs() >= 0.1;
          final intervalElapsed = last == null ||
              t.at.difference(last.timestamp).inSeconds >= 15;

          if (changed || intervalElapsed) {
            nextReadings = List<SensorReading>.from(prevReadings)
              ..add(SensorReading(
                timestamp: t.at,
                temperature: temp,
                doorOpen: false,
                compressorOn: true,
              ));
            if (nextTargetAt == null && temp <= session.profile.targetTemperature) {
              nextTargetAt = t.at;
            }
            shouldPersist = true;
          }
        }

        _activeSessions[i] = session.copyWith(
          readings: nextReadings,
          lastSeenAt: t.at,
          lastRssi: t.rssi,
          targetReachedAt: nextTargetAt,
        );
      }
    }

    if (shouldPersist) {
      unawaited(ActiveSessionsStore.saveSessions(_activeSessions));
    }
    notifyListeners();
  }

  /// Inicia uma nova sessão na bancada vinculando sensor, equipamento, técnico e T0.
  Future<BenchSession> startSession({
    required LiveTelemetry sensor,
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    String reportedSymptom = '',
  }) async {
    final existing = activeSessionForSensor(sensor.deviceId);
    if (existing != null) {
      throw Exception(
        'O sensor ${sensor.assetName} já está vinculado ao equipamento ${existing.serialNumber}.',
      );
    }

    final now = DateTime.now();
    final isSim = sensor.deviceId.startsWith('SIM-');
    final initialReadings = <SensorReading>[];
    if (sensor.temperatureC != null) {
      initialReadings.add(SensorReading(
        timestamp: now,
        temperature: sensor.temperatureC!,
        doorOpen: false,
        compressorOn: true,
      ));
    }

    final session = BenchSession(
      id: 'SES-${now.millisecondsSinceEpoch}',
      sensorId: sensor.deviceId,
      sensorName: sensor.assetName,
      serialNumber: serialNumber.trim(),
      modelName: modelName.trim(),
      technicianName: technicianName.trim(),
      profile: profile,
      reportedSymptom: reportedSymptom.trim(),
      startedAt: now,
      readings: initialReadings,
      isSimulated: isSim,
      dataSource: isSim ? 'Simulação de Bancada' : 'BLE Ao Vivo',
      lastSeenAt: sensor.at,
      lastRssi: sensor.rssi,
      targetReachedAt: (sensor.temperatureC != null &&
              sensor.temperatureC! <= profile.targetTemperature)
          ? now
          : null,
    );

    _activeSessions.insert(0, session);
    await ActiveSessionsStore.saveSessions(_activeSessions);
    await _syncWakelock();
    notifyListeners();
    return session;
  }

  Future<void> addNote(
    String sessionId,
    String text, {
    bool isDoorEvent = false,
  }) async {
    final idx = _activeSessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;

    final session = _activeSessions[idx];
    final now = DateTime.now();
    final updatedNotes = List<BenchNote>.from(session.manualNotes)
      ..add(BenchNote(timestamp: now, text: text.trim(), isDoorEvent: isDoorEvent));

    var updatedReadings = session.readings;
    if (isDoorEvent && session.readings.isNotEmpty) {
      updatedReadings = List<SensorReading>.from(session.readings)
        ..add(SensorReading(
          timestamp: now,
          temperature: session.readings.last.temperature,
          doorOpen: true,
          compressorOn: true,
        ));
    }

    _activeSessions[idx] = session.copyWith(
      manualNotes: updatedNotes,
      readings: updatedReadings,
    );
    await ActiveSessionsStore.saveSessions(_activeSessions);
    notifyListeners();
  }

  /// Puxa a memória flash interna do sensor ligado à sessão ativa e mescla
  /// pontos posteriores ao `startedAt` que tenham sido perdidos com app fechado.
  Future<int> mergeFlashHistoryIntoSession(String sessionId) async {
    final session = sessionById(sessionId);
    if (session == null) throw Exception('Sessão não encontrada.');
    if (session.isSimulated) {
      throw Exception('Sensores simulados não possuem memória flash física SCS.');
    }

    final download = await downloadFlashForSensor(session.sensorId);
    final cutoff = session.startedAt.subtract(const Duration(minutes: 2));
    final fresh = download.readings
        .where((r) => !r.timestamp.isBefore(cutoff))
        .toList();

    final idx = _activeSessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return 0;

    final current = _activeSessions[idx];
    final merged = List<SensorReading>.from(current.readings);
    int added = 0;

    for (final item in fresh) {
      final hasNearby = merged.any(
        (existing) =>
            existing.timestamp.difference(item.timestamp).inSeconds.abs() <= 20,
      );
      if (!hasNearby) {
        merged.add(item);
        added++;
      }
    }

    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _activeSessions[idx] = current.copyWith(
      readings: merged,
      dataSource: added > 0 ? 'BLE + Memória Flash SCS' : current.dataSource,
    );
    await ActiveSessionsStore.saveSessions(_activeSessions);
    notifyListeners();
    return added;
  }

  Future<TestResult> finalizeSession(
    String sessionId, {
    bool allowPartial = true,
  }) async {
    final idx = _activeSessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) throw Exception('Sessão não encontrada.');
    final session = _activeSessions[idx];

    final formattedNotes = session.manualNotes
        .map((n) =>
            '${n.timestamp.toLocal().toString().substring(11, 16)} — ${n.text}')
        .toList();

    final result = DiagnosticEngine.diagnose(
      serialNumber: session.serialNumber,
      modelName: session.modelName,
      technicianName: session.technicianName,
      profile: session.profile,
      readings: session.readings,
      sensorId: session.sensorId,
      sensorName: session.sensorName,
      reportedSymptom: session.reportedSymptom,
      dataSource: session.dataSource,
      isSimulated: session.isSimulated,
      manualNotes: formattedNotes,
      allowPartial: allowPartial,
    );

    await LocalReportStore.save(result, synced: false);
    _activeSessions.removeAt(idx);
    await ActiveSessionsStore.saveSessions(_activeSessions);
    _savedReports = await LocalReportStore.getAll();
    await _syncWakelock();
    notifyListeners();

    // Tenta envio em segundo plano sem bloquear ou falhar se estiver offline.
    return result;
  }

  Future<void> discardSession(String sessionId) async {
    _activeSessions.removeWhere((s) => s.id == sessionId);
    await ActiveSessionsStore.saveSessions(_activeSessions);
    await _syncWakelock();
    notifyListeners();
  }

  Future<FlashDownloadResult> downloadFlashForSensor(String sensorId) async {
    _isDownloadingFlash = true;
    notifyListeners();

    final prevSub = _radarSub;
    _radarSub = null;
    if (prevSub != null) {
      await prevSub.cancel();
    }

    try {
      await _ensurePermissions();
      final result = await _ble.downloadDecodedFlashHistory(sensorId);
      // Leitura concluída: volta a procurar os sensores.
      _isDownloadingFlash = false;
      _resumeRadarAfterFlash = false;
      notifyListeners();
      unawaited(startRadar(restart: true));
      return result;
    } catch (_) {
      // Falha ou tempo limite: a leitura PARA. O radar não religa sozinho
      // (antes ele voltava a ler o sensor por trás da tela de erro). Volta
      // quando o técnico sair da tela ou tocar em procurar de novo.
      _isDownloadingFlash = false;
      _scanning = false;
      notifyListeners();
      if (_resumeRadarAfterFlash) {
        // O técnico saiu da tela (ou cancelou) durante a leitura.
        _resumeRadarAfterFlash = false;
        unawaited(startRadar(restart: true));
      }
      rethrow;
    }
  }

  bool _resumeRadarAfterFlash = false;

  /// Etapa da leitura da memória flash (texto para a tela).
  ValueListenable<String> get flashStage => _ble.flashStage;

  /// Botão Cancelar da tela de memória flash.
  Future<void> cancelFlashDownload() => _ble.cancelFlashDownload();

  /// Retoma a busca de sensores (chamado ao sair da tela de memória flash).
  void resumeRadar() {
    if (_isDownloadingFlash) {
      // Ainda terminando a leitura: religa assim que ela acabar.
      _resumeRadarAfterFlash = true;
      return;
    }
    unawaited(startRadar());
  }

  Future<TestResult> createReportFromFlash({
    required String sensorId,
    required String sensorName,
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    required List<SensorReading> readings,
    String reportedSymptom = '',
  }) async {
    final result = DiagnosticEngine.diagnose(
      serialNumber: serialNumber.trim(),
      modelName: modelName.trim(),
      technicianName: technicianName.trim(),
      profile: profile,
      readings: readings,
      sensorId: sensorId,
      sensorName: sensorName,
      reportedSymptom: reportedSymptom.trim(),
      dataSource: 'Memória Flash SCS',
      isSimulated: false,
      allowPartial: true,
    );

    await LocalReportStore.save(result, synced: false);
    _savedReports = await LocalReportStore.getAll();
    notifyListeners();

    return result;
  }

  Future<void> deleteReport(String testId) async {
    await LocalReportStore.delete(testId);
    _savedReports = await LocalReportStore.getAll();
    notifyListeners();
  }

  LiveDiagnosticSnapshot evaluateSessionLive(BenchSession session) {
    return DiagnosticEngine.evaluateLive(
      profile: session.profile,
      readings: session.readings,
      startedAt: session.startedAt,
      reportedSymptom: session.reportedSymptom,
    );
  }

  Future<void> toggleDemoMode(bool enabled) async {
    _demoModeEnabled = enabled;
    await ActiveSessionsStore.saveDemoMode(enabled);
    if (enabled) {
      _startDemoTicker();
    } else {
      _demoTimer?.cancel();
      _demoTimer = null;
      _demoSensors.clear();
    }
    notifyListeners();
  }

  void _startDemoTicker() {
    _demoTimer?.cancel();
    _emitDemoTick();
    _demoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _emitDemoTick();
    });
  }

  void _emitDemoTick() {
    final now = DateTime.now();

    // Sensor demo 1: curva saudável (ideal para validar fluxo aprovado)
    final ses1 = activeSessionForSensor('SIM-COCA-01');
    double temp1 = 26.2 + ((now.second % 3) - 1) * 0.1;
    if (ses1 != null) {
      final step = ses1.readings.length;
      final targetFloor = ses1.profile.targetTemperature - 0.3;
      temp1 = (26.2 - step * 0.48).clamp(targetFloor, 26.8);
    }

    // Sensor demo 2: simula falha/estagnação após breve queda
    final ses2 = activeSessionForSensor('SIM-FAULT-02');
    double temp2 = 25.4 + ((now.second % 2) == 0 ? 0.1 : -0.1);
    if (ses2 != null) {
      final step = ses2.readings.length;
      if (step <= 4) {
        temp2 = 25.4 - step * 0.9; // cai rápido até ~21.8°C
      } else {
        temp2 = (21.8 + (step - 4) * 0.25).clamp(21.8, 24.1); // reaquece/estagna
      }
    }

    final listDemo = <LiveTelemetry>[
      LiveTelemetry(
        deviceId: 'SIM-COCA-01',
        at: now,
        temperatureC: double.parse(temp1.toStringAsFixed(1)),
        rssi: -52,
        assetName: 'SIM-GEUB031229',
        flagBytes: const [0x01, 0x00],
        rawHex: '01 00 [SIM]',
      ),
      LiveTelemetry(
        deviceId: 'SIM-FAULT-02',
        at: now,
        temperatureC: double.parse(temp2.toStringAsFixed(1)),
        rssi: -63,
        assetName: 'SIM-CERV-FALHA',
        flagBytes: const [0x01, 0x00],
        rawHex: '01 00 [SIM]',
      ),
    ];

    for (final t in listDemo) {
      _demoSensors[t.deviceId] = t;
    }

    bool shouldPersist = false;
    for (int i = 0; i < _activeSessions.length; i++) {
      final session = _activeSessions[i];
      if (!session.isSimulated) continue;
      final t = _demoSensors[session.sensorId];
      if (t == null || t.temperatureC == null) continue;

      final last = session.readings.isEmpty ? null : session.readings.last;
      final changed =
          last == null || (t.temperatureC! - last.temperature).abs() >= 0.1;
      final intervalElapsed =
          last == null || t.at.difference(last.timestamp).inSeconds >= 15;

      var nextReadings = session.readings;
      var nextTargetAt = session.targetReachedAt;
      if (changed || intervalElapsed) {
        nextReadings = List<SensorReading>.from(session.readings)
          ..add(SensorReading(
            timestamp: t.at,
            temperature: t.temperatureC!,
            doorOpen: false,
            compressorOn: true,
          ));
        if (nextTargetAt == null &&
            t.temperatureC! <= session.profile.targetTemperature) {
          nextTargetAt = t.at;
        }
        shouldPersist = true;
      }
      _activeSessions[i] = session.copyWith(
        readings: nextReadings,
        lastSeenAt: t.at,
        lastRssi: t.rssi,
        targetReachedAt: nextTargetAt,
      );
    }

    if (shouldPersist) {
      unawaited(ActiveSessionsStore.saveSessions(_activeSessions));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    unawaited(_radarSub?.cancel());
    unawaited(_ble.stopScan());
    unawaited(_ble.disconnect());
    super.dispose();
  }
}
