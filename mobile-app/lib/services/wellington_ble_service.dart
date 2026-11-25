import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';
import 'scs_event_log_reader.dart';
import 'scs_stats_decoder.dart';

/// Driver Bluetooth real para o sensor **Wellington Monitor (MON1-001)**.
///
/// O hardware não é um "AoFrio" genérico: é fabricado pela Wellington Drive
/// Technologies e fala o protocolo proprietário deles, chamado **SCS**
/// (Smart Cooler System). Ver `specs/wellington_scs_protocol.md` para a
/// origem de cada constante abaixo — todas vieram de engenharia reversa
/// do APK oficial (app "SCS Field"), lendo o bytecode ABC do `Main.swf`
/// (ActionScript), não de documentação do fabricante.
///
/// ## O que está CONFIRMADO (extraído do bytecode, não é achismo)
/// - Todos os UUIDs abaixo: lidos direto dos `const` da classe
///   `BluetoothLeCommsService` do app oficial.
/// - `requestStatus()`: o app oficial monta exatamente este pacote
///   (1 byte = código do comando) e escreve na característica
///   `reqDataCharacteristicUuid`, dentro do serviço `assetTrackServiceUuid`.
/// - Cabeçalho de 16 bytes de cada bloco de evento (`parseEventBlockHeader`).
///
/// ## Sobre autenticação: NÃO é necessária para ler dados
/// O app oficial tem uma característica `SCS_AUTH_CHARACTERISTIC` com
/// cripto AES-CBC, mas ela pertence a um fluxo SEPARADO e opcional
/// (trocar a chave de segurança do controlador, via
/// `SCS_DIAGNOSTIC_SERVICE`/`writeKeys`) — não é usada no fluxo normal de
/// conexão e leitura. Confirmado desmontando `onServicesDiscovered` →
/// `onSetNotificationSuccess` → `dispatchAuthenticateSuccess`: para
/// qualquer `productId` que não seja `PRODUCT_ID_SCS_GEN_1`/`PRODUCT_ID_CCC`
/// (inclui `PRODUCT_ID_MONITOR`), a "autenticação" é só ativar notificação
/// nas duas características de Asset Track abaixo — sem chave nenhuma.
///
/// ## O que NÃO está confirmado
/// - O layout exato de cada registro de temperatura dentro do bloco de
///   1024 bytes (depois do cabeçalho de 16 bytes já decodificado em
///   [parseEventBlockHeader]). Esse é o único gap real que falta — e dá
///   para fechar testando no hardware de verdade (não precisa mais de
///   decompilador nem de capturar o app oficial).
class WellingtonBleService {
  BluetoothDevice? _connectedDevice;
  bool _isConnected = false;

  // ── UUIDs confirmados (specs/wellington_scs_protocol.md) ──────────────

  /// SCS_ADMIN_SERVICE
  static const String adminServiceUuid =
      "6d90c7b0-a704-455f-92d1-9889ecaf636a";

  /// SCS_AUTH_CHARACTERISTIC — dentro de [adminServiceUuid]
  static const String authCharacteristicUuid =
      "34d81c0d-a398-4828-b702-8b7f42f5bf96";

  /// SCS_AUTH_RESPONSE_CHARACTERISTIC — dentro de [adminServiceUuid]
  static const String authResponseCharacteristicUuid =
      "673ebc29-fb79-4fbb-8b86-c3255a12f784";

  /// SCS_ASSET_TRACK_SERVICE — serviço principal de leitura de dados
  static const String assetTrackServiceUuid =
      "1deca38d-dc21-484e-83f2-e90866ac40b1";

  /// SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC — grava aqui os comandos
  /// (os códigos `scsRequest*` abaixo), 1 byte por comando.
  static const String reqDataCharacteristicUuid =
      "d224eeed-bb11-416d-b587-01d0dbee198b";

  /// SCS_ASSET_TRACK_RX_CHARACTERISTIC
  static const String assetTrackRxCharacteristicUuid =
      "0d3de66c-9b66-4d21-b2cf-9d4abb18e60d";

  /// SCS_ASSET_TRACK_TX_CHARACTERISTIC — notifica respostas de status/registro
  static const String assetTrackTxCharacteristicUuid =
      "efdd2460-6e34-4bc6-a262-32f0d30e8d65";

  /// SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC — notifica blocos de evento
  /// (histórico de temperatura) em massa
  static const String assetTrackBulkTxCharacteristicUuid =
      "ffdd2460-6e34-4bc6-a262-32f0d30e8d65";

  /// SCS_ASSET_TRACK_BOTTLER_ASSET_NUMBER
  static const String bottlerAssetNumberCharacteristicUuid =
      "23201dea-c8da-44c6-b170-136a597901e2";

  /// SCS_ASSET_TRACK_OEM_SERIAL_NUMBER
  static const String oemSerialNumberCharacteristicUuid =
      "864580ba-c669-4b97-b4ba-b729b7a30fa3";

  /// SCS_ASSET_TRACK_COOLER_MODEL
  static const String coolerModelCharacteristicUuid =
      "d8eb11c3-92c3-4195-9dc0-fee7ed5fa16b";

  /// SCS_DIAGNOSTIC_SERVICE
  static const String diagnosticServiceUuid =
      "e523405a-8273-407d-a8ab-f1bf20f45b19";

  /// SCS_DIAGNOSTIC_TX_CHARACTERISTIC
  static const String diagnosticTxCharacteristicUuid =
      "dcd9889f-c7a7-4344-8edc-c968f8e13ef0";

  /// SCS_DIAGNOSTIC_RX_CHARACTERISTIC
  static const String diagnosticRxCharacteristicUuid =
      "71d86c61-ffca-4a47-a6cd-b79650e6dcb3";

  // ── Códigos de comando SCS (enum "register id") ────────────────────────
  // Cada um é escrito como 1 byte em reqDataCharacteristicUuid.

  static const int scsRequestTimestamp = 1;
  static const int scsRequestStatus = 2;
  static const int scsRequestLifetimeCounts1 = 3;
  static const int scsRequestLifetimeCounts2 = 4;
  static const int scsRequestEventStartAddress = 5;
  static const int scsRequestResetLifetimeCountsOrStatsLog = 7;
  static const int scsSetBluetoothName = 8;
  static const int scsSetClock = 9;
  static const int scsRequestResetUserParams = 11;
  static const int scsRequestBluetoothName = 13;
  static const int scsRequestResetUserParamsSkipBootloader = 16;

  /// Tamanho padrão de bloco de evento quando o produto/firmware não
  /// informa outro (`DEFAULT_EVENT_BLOCK_SIZE` no app oficial).
  static const int defaultEventBlockSize = 1024;

  /// Código de identificação de produto "Monitor" no protocolo SCS
  /// (`PRODUCT_ID_MONITOR` no app oficial) — confirma que o Wellington
  /// Monitor é reconhecido nativamente pelo app, não é um produto à parte.
  static const int productIdMonitor = 16;

  BluetoothCharacteristic? _reqDataChar;
  BluetoothCharacteristic? _assetTrackTxChar;
  BluetoothCharacteristic? _bulkTxChar;
  BluetoothCharacteristic? _rxChar;
  bool _suspendWatchdog = false;

  /// Quanto tempo a última temperatura lida continua valendo quando só chegam
  /// pacotes de scan sem dados do fabricante.
  static const Duration _advHold = Duration(seconds: 30);

  /// Ouvintes criados em [connect]; cancelados em [disconnect] para o app não
  /// continuar processando o sensor depois que a leitura termina ou falha.
  final List<StreamSubscription<dynamic>> _connSubs = [];

  /// Etapa atual da leitura da memória flash, em texto simples para o técnico.
  final ValueNotifier<String> flashStage = ValueNotifier<String>('');

  bool _flashCancelled = false;

  /// Busca rápida (gasta mais bateria) só com ensaio rodando; senão, modo
  /// econômico. Vale a partir da próxima vez que a busca (re)começar.
  bool highFrequencyScan = false;

  /// Cancela a leitura da memória flash em andamento: desconecta na hora e a
  /// leitura termina com "Leitura cancelada".
  Future<void> cancelFlashDownload() async {
    _flashCancelled = true;
    await disconnect();
  }

  final _statusController = StreamController<Uint8List>.broadcast();
  final _eventBlockController = StreamController<Uint8List>.broadcast();

  /// Bytes brutos recebidos em [assetTrackTxCharacteristicUuid] (respostas
  /// a `requestStatus()`, etc.). Ainda não decodificados — ver o aviso
  /// no topo do arquivo sobre o que falta confirmar.
  Stream<Uint8List> get rawStatusNotifications => _statusController.stream;

  /// Blocos brutos de histórico recebidos em
  /// [assetTrackBulkTxCharacteristicUuid], em resposta a
  /// `requestEventLogFromStart()`. Cada bloco: 16 bytes de cabeçalho
  /// confirmado ([parseEventBlockHeader]) + até 1024 bytes de corpo cujo
  /// layout ainda não foi decodificado (ver topo do arquivo).
  Stream<Uint8List> get rawEventBlocks => _eventBlockController.stream;

  bool get isConnected => _isConnected;

  /// Nomes de todos os periféricos BLE vistos no último scan (diagnóstico:
  /// mostrado na tela quando nenhum Monitor é reconhecido).
  List<String> lastSeenDevices = const [];

  /// Dados de anúncio por dispositivo (fabricante = tipo de produto SCS).
  final Map<String, String> _advInfo = {};

  /// Série temporal de payloads do fabricante (0x578) vistos no anúncio,
  /// por dispositivo. Chave = deviceId. Usado para achar o campo de
  /// temperatura que o sensor transmite sem autenticação.
  final Map<String, List<_AdvSample>> _advSamples = {};

  Stream<List<DiscoveredDevice>> scanForDevices() async* {
    // No iOS o adaptador começa em "unknown"; escanear antes de "on" não acha nada.
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw Exception('Bluetooth desligado ou sem permissão. Ative o Bluetooth e '
          'permita o acesso em Ajustes > ISO Test.');
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));

    yield* FlutterBluePlus.scanResults.map((results) {
      lastSeenDevices = (results.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)))
          .map((r) => '${_nameOf(r).isEmpty ? '(sem nome)' : _nameOf(r)} ${r.rssi}dBm')
          .take(8)
          .toList();
      for (final r in results) {
        final wellington = r.advertisementData.manufacturerData[0x578];
        if (wellington != null) {
          final list = _advSamples.putIfAbsent(r.device.remoteId.str, () => []);
          final hex = wellington.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          if (list.isEmpty || list.last.hex != hex) {
            if (list.length < 60) list.add(_AdvSample(DateTime.now(), hex, List<int>.from(wellington)));
          }
        }
        final mfr = r.advertisementData.manufacturerData.entries
            .map((e) => '0x${e.key.toRadixString(16)}:${e.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}')
            .join(' | ');
        _advInfo[r.device.remoteId.str] =
            'nome=${_nameOf(r)} rssi=${r.rssi} mfr=[$mfr] svc=${r.advertisementData.serviceUuids.map((u) => u.str128.substring(0, 8)).join(',')} '
            'svcData=${r.advertisementData.serviceData.entries.map((e) => '${e.key.str128.substring(0, 8)}:${e.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}').join(' | ')}';
      }
      return results
          .where(_isWellingtonMonitor)
          .map((r) => DiscoveredDevice(
                id: r.device.remoteId.str,
                name: _nameOf(r).isEmpty ? r.device.remoteId.str : _nameOf(r),
                rssi: r.rssi,
              ))
          .toList();
    });
  }

  /// Decodifica a série de anúncios: para cada posição par do payload,
  /// mostra o int16 little-endian /100 e /10, destacando valores numa faixa
  /// de temperatura física (-40..60 °C). Se algum acompanhar a temperatura
  /// real entre amostras, achamos o campo de telemetria livre de auth.
  void _dumpAdvSamples(String deviceId) {
    final samples = _advSamples[deviceId] ?? const [];
    _log('ADV_SAMPLES ${samples.length} payloads distintos do fabricante 0x578');
    for (final s in samples) {
      _log('  @${s.at.toIso8601String().substring(11, 19)} ${s.hex}');
      final cands = <String>[];
      for (int off = 0; off + 1 < s.bytes.length; off++) {
        final v = s.bytes[off] | (s.bytes[off + 1] << 8);
        final signed = v >= 0x8000 ? v - 0x10000 : v;
        for (final div in [100.0, 10.0]) {
          final t = signed / div;
          if (t >= -40 && t <= 60) cands.add('off$off/${div.toInt()}=${t.toStringAsFixed(2)}');
        }
      }
      if (cands.isNotEmpty) _log('     cand °C: ${cands.join('  ')}');
    }
  }

  /// Temperatura ao vivo que o Monitor transmite no anúncio BLE, SEM
  /// autenticação. Formato confirmado no hardware (asset GEUB031229):
  /// payload do fabricante 0x578 = `01 00` [header] + int16 LE em
  /// centésimos de °C (bytes 2-3) + nome do asset em ASCII.
  ///   `01 00 c4 09 ...` = 0x09c4 = 2500 = 25.00 °C
  ///   `01 00 1e 0a ...` = 0x0a1e = 2590 = 25.90 °C (sobe ao aquecer)
  /// Retorna null se o payload for curto demais ou a temperatura cair fora
  /// da faixa física (-40..60 °C) — nunca inventa leitura.
  static double? decodeAdvTemp(List<int> bytes) {
    if (bytes.length < 4) return null;
    final raw = bytes[2] | (bytes[3] << 8);
    final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
    final t = signed / 100.0;
    return (t >= -40 && t <= 60) ? t : null;
  }

  /// Junta um pacote de anúncio ao último estado conhecido do sensor.
  ///
  /// O Monitor alterna dois pacotes: um com os dados do fabricante (0x578:
  /// temperatura + nome do ativo, ex.: GEUB031229) e a resposta de scan (só o
  /// serial B152E…). Regras:
  /// - pacote do fabricante atualiza temperatura e nome (o nome do ativo, uma
  ///   vez lido, nunca volta para o serial);
  /// - resposta de scan só atualiza o sinal e mantém nome e temperatura;
  /// - sem pacote do fabricante há mais de [_advHold], a temperatura vira null
  ///   (nunca mostra valor velho como atual), mas o nome fica.
  static LiveTelemetry mergeAdvertisement({
    required String deviceId,
    required LiveTelemetry? prev,
    required List<int>? mfr,
    required String scanName,
    required int rssi,
    required DateTime now,
    required DateTime? lastMfrAt,
  }) {
    if (mfr != null) {
      final tail = _asciiTail(mfr);
      final name = tail.isNotEmpty
          ? tail
          : (prev?.assetName ?? (scanName.isEmpty ? deviceId : scanName));
      return LiveTelemetry(
        deviceId: deviceId,
        at: now,
        temperatureC: decodeAdvTemp(mfr) ?? prev?.temperatureC,
        rssi: rssi,
        assetName: name,
        flagBytes: mfr.length >= 2 ? [mfr[0], mfr[1]] : List<int>.from(mfr),
        rawHex: mfr.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
      );
    }
    if (prev == null) {
      return LiveTelemetry(
        deviceId: deviceId,
        at: now,
        temperatureC: null,
        rssi: rssi,
        assetName: scanName.isEmpty ? deviceId : scanName,
        flagBytes: const [],
        rawHex: '',
      );
    }
    final fresh = lastMfrAt != null && now.difference(lastMfrAt) < _advHold;
    return LiveTelemetry(
      deviceId: deviceId,
      at: prev.at,
      temperatureC: fresh ? prev.temperatureC : null,
      rssi: rssi,
      assetName: prev.assetName,
      flagBytes: prev.flagBytes,
      rawHex: prev.rawHex,
    );
  }

  /// Janela de captura ao vivo (pull-down) quando o histórico interno está
  /// travado. Ajustável pela tela: quanto maior, mais pontos da curva.
  Duration liveCaptureWindow = const Duration(seconds: 20);

  /// Telemetria ao vivo de TODOS os sensores próximos, direto do anúncio BLE,
  /// SEM conexão e SEM auth. A cada atualização emite a lista de todos os
  /// Monitors que anunciam o payload 0x578, ordenada por sinal (maior RSSI
  /// primeiro). Mantém o último anúncio de cada sensor para a lista não
  /// "piscar" quando um pacote chega só de um deles. Usa
  /// [AndroidScanMode.lowLatency] e `continuousUpdates` para receber o mesmo
  /// sensor repetidamente.
  ///
  /// iOS: o anúncio de fabricante (0x578) NÃO chega com o app em segundo plano
  /// sem filtro de serviço — mantenha o app em primeiro plano durante a leitura.
  Stream<List<LiveTelemetry>> watchAllLiveTelemetry() async* {
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw Exception('Bluetooth desligado ou sem permissão. Ative o Bluetooth e '
          'permita o acesso em Ajustes > ISO Test.');
    }
    final latest = <String, LiveTelemetry>{};
    // Último pacote do fabricante (0x578) visto de cada sensor.
    final lastMfrAt = <String, DateTime>{};
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidScanMode: highFrequencyScan ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      androidUsesFineLocation: false,
    );
    // Vigia religa a busca se o sistema parar (10 s: menos bateria que os 3 s anteriores).
    final watchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_suspendWatchdog && !_isConnected && !FlutterBluePlus.isScanningNow) {
        try {
          await FlutterBluePlus.startScan(
            continuousUpdates: true,
            androidScanMode: highFrequencyScan ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
            androidUsesFineLocation: false,
          );
        } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
      }
    });
    try {
      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          final w = r.advertisementData.manufacturerData[0x578];
          if (w == null && !_isWellingtonMonitor(r)) continue;
          final id = r.device.remoteId.str;
          final now = DateTime.now();
          latest[id] = mergeAdvertisement(
            deviceId: id,
            prev: latest[id],
            mfr: w,
            scanName: _nameOf(r),
            rssi: r.rssi,
            now: now,
            lastMfrAt: lastMfrAt[id],
          );
          if (w != null) lastMfrAt[id] = now;
        }
        if (latest.isEmpty) continue;
        final list = latest.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
        yield list;
      }
    } finally {
      watchdog.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
    }
  }

  /// Grava a curva de pull-down ao vivo pelo anúncio BLE, usando SÓ o decoder
  /// confirmado no hardware ([decodeAdvTemp], centésimos de °C). Trava no sensor
  /// de maior sinal na primeira leitura e o acompanha por [window], com horário
  /// real (`DateTime.now()`). Registra um ponto quando a temperatura muda
  /// (≥0.1 °C) ou a cada 15 s de estabilidade — nunca inventa leitura.
  ///
  /// iOS: exige o app em primeiro plano (anúncio de fabricante não chega em
  /// background sem filtro de serviço). Por isso a UI pede "mantenha o app
  /// aberto durante o ensaio".
  Future<List<SensorReading>> captureLiveCurve(Duration window) async {
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw Exception('Bluetooth desligado ou sem permissão. Ative o Bluetooth e '
          'permita o acesso em Ajustes > ISO Test.');
    }
    final readings = <SensorReading>[];
    String? targetId;
    double? lastTemp;

    void handle(List<ScanResult> results) {
      ScanResult? best;
      for (final r in results) {
        final w = r.advertisementData.manufacturerData[0x578];
        if (w == null || !_isWellingtonMonitor(r)) continue;
        if (targetId != null && r.device.remoteId.str != targetId) continue;
        if (best == null || r.rssi > best.rssi) best = r;
      }
      if (best == null) return;
      targetId ??= best.device.remoteId.str;
      final t = decodeAdvTemp(best.advertisementData.manufacturerData[0x578]!);
      if (t == null) return;
      final now = DateTime.now();
      final last = lastTemp;
      final changed = last == null || (t - last).abs() >= 0.1;
      final stale = readings.isEmpty ||
          now.difference(readings.last.timestamp).inSeconds >= 15;
      if (changed || stale) {
        readings.add(SensorReading(timestamp: now, temperature: t));
        lastTemp = t;
      }
    }

    // Reinicia o scan se ele morreu (iOS/Android suspendem o BLE quando o app
    // vai pra segundo plano ou a tela bloqueia). Sem isto, voltar ao app deixava
    // o scan parado e o laudo terminava com poucas leituras ("teste falhou").
    Future<void> ensureScan() async {
      if (FlutterBluePlus.isScanningNow) return;
      try {
        await FlutterBluePlus.startScan(
          continuousUpdates: true,
          androidScanMode: AndroidScanMode.lowLatency,
          androidUsesFineLocation: false,
        );
      } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
    }

    final sub = FlutterBluePlus.scanResults.listen(handle);
    final deadline = DateTime.now().add(window);
    try {
      await ensureScan();
      // ponytail: poll de 3s re-arma o scan após retomar do background; tempo é
      // relógio de parede, então a janela total continua correta mesmo suspenso.
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 3));
        await ensureScan();
      }
    } finally {
      await sub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
    }
    return readings;
  }

  /// Nome do asset em ASCII imprimível no fim do payload (depois da temperatura).
  static String _asciiTail(List<int> bytes) {
    final sb = StringBuffer();
    for (int i = 4; i < bytes.length; i++) {
      final c = bytes[i];
      if (c >= 32 && c <= 126) sb.writeCharCode(c);
    }
    return sb.toString().trim();
  }

  /// Desconecta e fica ouvindo o anúncio do sensor por [duration], montando
  /// a curva de temperatura ao vivo a partir do campo livre de auth
  /// ([decodeAdvTemp]). Cada payload distinto vira um [SensorReading] com
  /// seu horário. Chamado quando o histórico via conexão não vem.
  Future<List<SensorReading>> _watchAdvertisementTemperature(Duration duration) async {
    final id = _connectedDevice?.remoteId.str;
    if (id == null) return const [];
    _log('ADV_WATCH desconectando para curva ao vivo por ${duration.inSeconds}s…');
    _advSamples.remove(id);
    try {
      await _connectedDevice!.disconnect();
    } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
    try {
      await FlutterBluePlus.startScan(timeout: duration, androidUsesFineLocation: false);
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.device.remoteId.str != id) continue;
          final w = r.advertisementData.manufacturerData[0x578];
          if (w == null) continue;
          final hex = w.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          final list = _advSamples.putIfAbsent(id, () => []);
          if ((list.isEmpty || list.last.hex != hex) && list.length < 2000) {
            list.add(_AdvSample(DateTime.now(), hex, List<int>.from(w)));
          }
        }
      });
      await Future.delayed(duration);
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _log('ADV_WATCH falhou: $e');
    }
    _dumpAdvSamples(id);
    final readings = <SensorReading>[];
    for (final s in _advSamples[id] ?? const <_AdvSample>[]) {
      final t = decodeAdvTemp(s.bytes);
      if (t != null) readings.add(SensorReading(timestamp: s.at, temperature: t));
    }
    _log('ADV_WATCH ${readings.length} leituras ao vivo decodificadas');
    return readings;
  }

  /// No iOS `platformName` vem vazio antes de conectar; o nome anunciado
  /// fica em `advName`.
  static String _nameOf(ScanResult r) =>
      r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;

  /// Aceita quem anuncia o serviço SCS Asset Track ou tem nome no padrão do
  /// serial da etiqueta (ex.: "B152E02371079226226").
  static bool _isWellingtonMonitor(ScanResult r) =>
      r.advertisementData.serviceUuids.any((u) => u.str128.toLowerCase() == assetTrackServiceUuid) ||
      _looksLikeWellingtonMonitor(_nameOf(r));

  static bool _looksLikeWellingtonMonitor(String name) {
    // Serial da etiqueta sempre começa com "B15" neste lote; ajuste aqui
    // se outros sensores tiverem prefixo diferente.
    return RegExp(r'^[A-Z0-9]{10,}$').hasMatch(name);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<bool> connect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    // Guardado ANTES de conectar: se a conexão falhar no meio, [disconnect]
    // ainda consegue encerrar tudo.
    _connectedDevice = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

    final services = await device.discoverServices();

    final assetTrack = services.firstWhere(
      (s) => s.uuid.str128.toLowerCase() == assetTrackServiceUuid,
      orElse: () => throw Exception(
          'SCS_ASSET_TRACK_SERVICE não encontrado — não é um Wellington Monitor?'),
    );

    _reqDataChar = assetTrack.characteristics.firstWhere(
      (c) => c.uuid.str128.toLowerCase() == reqDataCharacteristicUuid,
    );
    _assetTrackTxChar = assetTrack.characteristics.firstWhere(
      (c) => c.uuid.str128.toLowerCase() == assetTrackTxCharacteristicUuid,
    );
    _bulkTxChar = assetTrack.characteristics.firstWhere(
      (c) => c.uuid.str128.toLowerCase() == assetTrackBulkTxCharacteristicUuid,
    );
    // Opcional: sem ele só o laudo ao vivo funciona, o download do log não.
    _rxChar = assetTrack.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
          (c) => c!.uuid.str128.toLowerCase() == assetTrackRxCharacteristicUuid,
          orElse: () => null,
        );

    rawLog.clear();
    _log('CONECTADO $deviceId; serviços: ${services.map((s) => s.uuid.str128.substring(0, 8)).join(',')}');
    _log('ADV ${_advInfo[deviceId] ?? '(sem dados de anúncio)'}');
    _dumpAdvSamples(deviceId);
    _log('MTU ${device.mtuNow}');
    // Diagnóstico (só leitura + inscrição, nada é escrito): todos os serviços.
    for (final svc in services) {
      final s8 = svc.uuid.str128.substring(0, 8);
      for (final c in svc.characteristics) {
        final c8 = c.uuid.str128.substring(0, 8);
        final p = c.properties;
        _log('CHAR $s8/$c8 ${[if (p.read) 'R', if (p.write) 'W', if (p.writeWithoutResponse) 'WNR', if (p.notify) 'N', if (p.indicate) 'I'].join('')}');
        if (p.read) {
          try {
            _log('READ $s8/$c8', await c.read());
          } catch (e) {
            _log('READ $s8/$c8 falhou: $e');
          }
        }
        final isAssetTx = c.uuid.str128.toLowerCase() == assetTrackTxCharacteristicUuid ||
            c.uuid.str128.toLowerCase() == assetTrackBulkTxCharacteristicUuid;
        if ((p.notify || p.indicate) && !isAssetTx) {
          try {
            await c.setNotifyValue(true);
            _connSubs.add(c.onValueReceived.listen((v) => _log('NOTIF $s8/$c8', v)));
            _log('NOTIFY ON $s8/$c8');
          } catch (e) {
            _log('NOTIFY $s8/$c8 falhou: $e');
          }
        }
      }
    }

    // Ativar notificação em ambas as características é tudo que o "handshake"
    // de autenticação exige para o Monitor — ver nota no topo do arquivo.
    _log('NOTIFY TX efdd2460 -> ${await _assetTrackTxChar!.setNotifyValue(true)}');
    _connSubs.add(_assetTrackTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      _log('TX', bytes);
      _statusController.add(Uint8List.fromList(bytes));
    }));

    _log('NOTIFY BULK ffdd2460 -> ${await _bulkTxChar!.setNotifyValue(true)}');
    _connSubs.add(_bulkTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      _log('BULK', bytes);
      _eventBlockController.add(Uint8List.fromList(bytes));
    }));

    _isConnected = true;
    return true;
  }

  /// Relógio do sensor (cmd 1). Resposta: [1, timestamp u32 LE] pelo canal TX.
  /// Com ele: offset = (Unix agora) − timestamp do sensor.
  Future<int> requestSensorTimestamp() async {
    final req = _reqDataChar;
    if (req == null) throw Exception('Não conectado.');
    final completer = Completer<int>();
    late StreamSubscription<Uint8List> sub;
    sub = rawStatusNotifications.listen((d) {
      if (d.length >= 5 && d[0] == scsRequestTimestamp && !completer.isCompleted) {
        completer.complete(ByteData.sublistView(d).getUint32(1, Endian.little));
      }
    });
    try {
      await req.write([scsRequestTimestamp], withoutResponse: false);
      return await completer.future.timeout(const Duration(seconds: 3));
    } finally {
      await sub.cancel();
    }
  }

  /// Baixa o log de páginas do sensor (protocolo do app oficial). Não usado pelo
  /// laudo ainda: falta validar com hardware. [protocolVersion] e [fastRead]
  /// vêm do dispositivo (fastRead: controllerCodeRevision >= 4 no Monitor).
  Future<List<ScsEventBlock>> downloadEventLog({
    required int reqTimeSecs,
    required int protocolVersion,
    required bool fastRead,
  }) async {
    final req = _reqDataChar;
    final rx = _rxChar;
    if (req == null || rx == null) throw Exception('Não conectado.');
    final reader = ScsEventLogReader(
      writeReqData: (b) => req.write(b.toList(), withoutResponse: false),
      writeRx: (b) => rx.write(b.toList(), withoutResponse: false),
      tx: rawStatusNotifications,
      bulk: rawEventBlocks,
      protocolVersion: protocolVersion,
      fastRead: fastRead,
    );
    try {
      return await reader.readEventLog(reqTimeSecs: reqTimeSecs);
    } finally {
      await reader.dispose();
    }
  }

  /// Diagnóstico do log de páginas, para validar o protocolo com hardware real.
  /// Procura o Monitor, conecta, sincroniza o relógio, baixa o log, decodifica
  /// e desconecta. Devolve linhas de texto para mostrar ao técnico.
  /// protocolVersion 70 é suposição: o bloco traz o valor real (ver última linha).
  Future<List<String>> runEventLogDiagnostic() async {
    const assumedProtocolVersion = 70;
    final lines = <String>[];
    final id = await _findMonitorId();
    if (id == null) {
      return ['Nenhum Monitor encontrado em 12 s. Aproxime o sensor e tente de novo.'];
    }
    lines.add('Monitor: $id');
    await connect(id);
    try {
      final sensorTs = await requestSensorTimestamp();
      final offset = DateTime.now().millisecondsSinceEpoch ~/ 1000 - sensorTs;
      lines.add('Relógio do sensor: $sensorTs s (offset ${offset}s)');

      var fast = true;
      List<ScsEventBlock> blocks;
      try {
        blocks = await downloadEventLog(
            reqTimeSecs: 0, protocolVersion: assumedProtocolVersion, fastRead: true);
      } catch (e) {
        lines.add('Modo rápido falhou ($e). Tentando modo normal.');
        fast = false;
        blocks = await downloadEventLog(
            reqTimeSecs: 0, protocolVersion: assumedProtocolVersion, fastRead: false);
      }
      lines.add('Modo: ${fast ? 'rápido' : 'normal'}. Blocos válidos: ${blocks.length}');

      final readings = decodeStatsV2(
        blocks: blocks,
        sensorToUnixOffsetSecs: offset,
        protocolVersion: assumedProtocolVersion,
      );
      lines.add('Leituras de temperatura: ${readings.length}');
      if (readings.isNotEmpty) {
        final a = readings.first;
        final b = readings.last;
        lines.add('Primeira: ${a.temperature.toStringAsFixed(1)} °C em ${a.timestamp.toLocal()}');
        lines.add('Última: ${b.temperature.toStringAsFixed(1)} °C em ${b.timestamp.toLocal()}');
      }
      if (blocks.isNotEmpty) {
        lines.add('protocolVersion real no bloco: ${blocks.first.protocolVersion}');
        lines.add('Status do 1º bloco: 0x${blocks.first.status.toRadixString(16)}');
      }
    } finally {
      await disconnect();
    }
    return lines;
  }

  /// Conecta em um sensor específico, lê o relógio RTC, baixa páginas da memória
  /// flash via protocolo SCS Field (`cmd 5/1/3`) e decodifica com `decodeStatsV2`,
  /// usando a versão real de protocolo informada pelo primeiro bloco.
  Future<FlashDownloadResult> downloadDecodedFlashHistory(
    String deviceId, {
    int reqTimeSecs = 0,
  }) async {
    const assumedProtocolVersion = 70;
    final lines = <String>['Sensor alvo: $deviceId'];

    _suspendWatchdog = true;
    _flashCancelled = false;
    try {
      await stopScan();
    } catch (e) {
      debugPrint('flash: stopScan falhou: $e');
    }

    try {
      // Conexão DENTRO do try: se falhar ou estourar o tempo, o finally abaixo
      // desconecta e para tudo (antes a conexão ficava aberta lendo o sensor).
      flashStage.value = 'Conectando ao sensor...';
      await connect(deviceId);
      flashStage.value = 'Lendo o relógio do sensor...';
      // Uma nova tentativa: no iPhone a primeira resposta às vezes se perde.
      int sensorTs;
      try {
        sensorTs = await requestSensorTimestamp();
      } on TimeoutException {
        if (_flashCancelled) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 700));
        sensorTs = await requestSensorTimestamp();
      }
      final offset = DateTime.now().millisecondsSinceEpoch ~/ 1000 - sensorTs;
      lines.add('Relógio RTC do sensor: $sensorTs s (offset ${offset}s)');

      flashStage.value = 'Baixando o histórico de temperatura...';
      var fast = true;
      List<ScsEventBlock> blocks;
      try {
        blocks = await downloadEventLog(
          reqTimeSecs: reqTimeSecs,
          protocolVersion: assumedProtocolVersion,
          fastRead: true,
        );
      } catch (e) {
        lines.add('Modo rápido falhou ($e). Alternando para leitura chunk a chunk.');
        fast = false;
        blocks = await downloadEventLog(
          reqTimeSecs: reqTimeSecs,
          protocolVersion: assumedProtocolVersion,
          fastRead: false,
        );
      }
      lines.add('Modo de leitura: ${fast ? 'rápido (BULK)' : 'normal (TX)'} • Blocos válidos: ${blocks.length}');

      final realPv = (blocks.isNotEmpty && blocks.first.protocolVersion > 0)
          ? blocks.first.protocolVersion
          : assumedProtocolVersion;

      flashStage.value = 'Organizando as leituras...';
      final readings = decodeStatsV2(
        blocks: blocks,
        sensorToUnixOffsetSecs: offset,
        protocolVersion: realPv,
      )..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      lines.add('protocolVersion detectado: $realPv');
      lines.add('Leituras térmicas decodificadas: ${readings.length}');
      if (readings.isNotEmpty) {
        lines.add('Início: ${readings.first.temperature.toStringAsFixed(1)}°C em ${readings.first.timestamp.toLocal()}');
        lines.add('Fim: ${readings.last.temperature.toStringAsFixed(1)}°C em ${readings.last.timestamp.toLocal()}');
      }

      return FlashDownloadResult(
        deviceId: deviceId,
        sensorTimestamp: sensorTs,
        offsetSeconds: offset,
        usedFastMode: fast,
        blockCount: blocks.length,
        protocolVersion: realPv,
        firstBlockStatus: blocks.isNotEmpty ? blocks.first.status : null,
        readings: readings,
        diagnosticLines: lines,
      );
    } catch (e) {
      if (_flashCancelled) throw Exception('Leitura cancelada.');
      if (e is TimeoutException) {
        throw Exception('O sensor não respondeu a tempo. A leitura foi encerrada. '
            'Aproxime o celular do sensor e toque em Tentar novamente.');
      }
      rethrow;
    } finally {
      await disconnect();
      _suspendWatchdog = false;
      flashStage.value = '';
    }
  }

  /// Procura um Monitor no scan (12 s) e devolve o id do dispositivo, ou null.
  Future<String?> _findMonitorId() async {
    final found = Completer<String?>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.manufacturerData[0x578] != null &&
            _isWellingtonMonitor(r) &&
            !found.isCompleted) {
          found.complete(r.device.remoteId.str);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: false,
      );
      return await found.future.timeout(const Duration(seconds: 12), onTimeout: () => null);
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  /// Envia o comando `SCS_REQUEST_STATUS` (código 2). Formato confirmado
  /// por engenharia reversa do app oficial (método `startReadStatus`):
  /// um `ByteArray` de 1 byte, só com o código do comando.
  Future<void> requestStatus() async {
    if (_reqDataChar == null) throw Exception('Não conectado.');
    await _writeCommand(scsRequestStatus);
  }

  Future<void> _writeCommand(int commandCode) async {
    _log('WRITE cmd=$commandCode');
    try {
      await _reqDataChar!.write([commandCode], withoutResponse: false);
    } catch (e) {
      _log('WRITE cmd=$commandCode falhou: $e');
      rethrow;
    }
  }

  /// Registro bruto da sessão BLE (comandos, notificações em hex). Usado no
  /// botão "Copiar diagnóstico" para fechar o formato real das respostas SCS.
  final List<String> rawLog = [];

  void _log(String label, [List<int>? bytes]) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    final hex = bytes == null
        ? ''
        : ' [${bytes.length}] ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
    if (rawLog.length < 400) rawLog.add('$t $label$hex');
  }

  /// Pede o histórico de eventos a partir do endereço inicial
  /// (`SCS_REQUEST_EVENT_START_ADDRESS`, comando confirmado). A resposta
  /// chega em [rawEventBlocks].
  Future<void> requestEventLogFromStart() async {
    if (_reqDataChar == null) throw Exception('Não conectado.');
    await _writeCommand(scsRequestEventStartAddress);
  }

  Future<void> _waitForBlocks(List<Uint8List> list) async {
    for (int i = 0; i < 20; i++) {
      if (list.isNotEmpty) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// NÃO usado no laudo: o layout dos registros dentro do bloco de 1024 bytes
  /// ainda não foi confirmado no hardware (ver aviso no topo). O laudo é gerado
  /// por [captureLiveCurve], que usa só o decoder confirmado do anúncio.
  /// Mantido para quando o formato do bloco for fechado via conexão.
  Future<List<SensorReading>> downloadStoredHistory() async {
    if (_connectedDevice == null) throw Exception('Nenhum sensor conectado.');
    if (_reqDataChar == null) throw Exception('Canal de comunicação não inicializado.');

    final List<SensorReading> readings = [];
    final List<Uint8List> receivedBlocks = [];

    // Subscrição para coletar blocos de eventos via bulk TX
    final subscription = rawEventBlocks.listen((block) {
      if (block.isNotEmpty) {
        receivedBlocks.add(block);
      }
    });

    try {
      // 1. Envia comando para descarregar o histórico da memória flash
      await requestEventLogFromStart();

      // Aguarda receber blocos ou até timeout
      await Future.any([
        Future.delayed(const Duration(seconds: 4)),
        _waitForBlocks(receivedBlocks),
      ]);
    } catch (e) {
      _log('ERRO pedindo histórico: $e');
    }

    await subscription.cancel();

    // 2. Decodifica os blocos recebidos
    for (final block in receivedBlocks) {
      final decoded = parseBlockRecords(block);
      readings.addAll(decoded);
    }

    // 3. Se nenhum bloco foi retornado (ex: memória vazia ou sensor em novo ciclo),
    // consulta a telemetria em tempo real
    if (readings.isEmpty) {
      final liveReading = await _pollLiveTelemetry();
      if (liveReading != null) {
        readings.add(liveReading);
      }
    }

    if (readings.isEmpty) {
      // Diagnóstico: pede relógio e status de novo e espera respostas brutas.
      for (final cmd in [scsRequestTimestamp, scsRequestStatus, scsRequestEventStartAddress]) {
        try {
          await _writeCommand(cmd);
        } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      _log('FIM comandos: ${receivedBlocks.length} blocos BULK, nada decodificado');
      // Histórico interno travado: monta a curva pull-down ao vivo a partir
      // da temperatura que o sensor transmite no anúncio (sem autenticação).
      readings.addAll(await _watchAdvertisementTemperature(liveCaptureWindow));
    }

    // Nunca inventar leitura: lista vazia volta para a tela, que mostra
    // "sensor não retornou leituras" em vez de gerar laudo com dado falso.
    readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return readings;
  }

  Future<SensorReading?> _pollLiveTelemetry() async {
    try {
      if (_reqDataChar == null) return null;
      final completer = Completer<SensorReading?>();
      late StreamSubscription sub;

      sub = rawStatusNotifications.listen((data) {
        if (data.length >= 2) {
          final bd = ByteData.sublistView(data);
          final raw = bd.getInt16(0, Endian.little);
          if (raw < -400 || raw > 600) return; // fora da faixa física: ignora
          final temp = raw / 10.0;
          sub.cancel();
          if (!completer.isCompleted) {
            completer.complete(SensorReading(
              timestamp: DateTime.now(),
              temperature: temp,
              doorOpen: false,
            ));
          }
        }
      });

      await requestStatus();

      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          sub.cancel();
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodifica registros de temperatura e eventos dentro de um bloco de memória Wellington SCS
  static List<SensorReading> parseBlockRecords(Uint8List block) {
    if (block.length < 16) return [];
    final List<SensorReading> results = [];

    try {
      final header = parseEventBlockHeader(block);
      DateTime baseTime;
      // Se rawTimestamp for razoável (após ano 2020), usa como epoch UTC
      if (header.rawTimestamp > 1577836800 && header.rawTimestamp < 2000000000) {
        baseTime = DateTime.fromMillisecondsSinceEpoch(header.rawTimestamp * 1000, isUtc: true);
      } else {
        baseTime = DateTime.now().subtract(Duration(minutes: (block.length - 16) ~/ 2));
      }

      final bd = ByteData.sublistView(block);
      int offset = 16;
      int sampleIndex = 0;

      // Percorre os dados em pares de 2 bytes (inteiros little-endian de 16 bits)
      // No protocolo SCS, estatísticas periódicas são registradas a cada minuto
      while (offset + 1 < block.length) {
        final rawVal = bd.getInt16(offset, Endian.little);
        offset += 2;

        bool isDoorOpen = false;
        double? temp;

        if (rawVal >= -400 && rawVal <= 600) {
          temp = rawVal / 10.0;
        } else if ((rawVal & 0x7FFF) >= 0 && (rawVal & 0x7FFF) <= 600) {
          isDoorOpen = (rawVal & 0x8000) != 0;
          temp = (rawVal & 0x7FFF) / 10.0;
        }

        if (temp != null) {
          final sampleTime = baseTime.add(Duration(minutes: sampleIndex++));
          results.add(SensorReading(
            timestamp: sampleTime,
            temperature: double.parse(temp.toStringAsFixed(1)),
            doorOpen: isDoorOpen,
          ));
        }
      }
    } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }

    return results;
  }

  /// Decodifica o cabeçalho de 16 bytes de um bloco de evento — formato
  /// confirmado via bytecode (método interno `_-9U` de
  /// `BluetoothLeCommsService`, que lê exatamente estes campos antes de
  /// processar os registros do bloco).
  static EventBlockHeader parseEventBlockHeader(Uint8List block) {
    if (block.length < 16) {
      throw ArgumentError('Bloco de evento precisa de pelo menos 16 bytes.');
    }
    final bd = ByteData.sublistView(block);
    return EventBlockHeader(
      rawTimestamp: bd.getUint32(0, Endian.little),
      status: bd.getUint16(4, Endian.little),
      protocolVersion: bd.getUint16(6, Endian.little),
      reserved: bd.getUint16(8, Endian.little),
    );
  }

  Future<void> disconnect() async {
    // Para de ouvir o sensor primeiro: nada mais é lido depois daqui.
    for (final s in _connSubs) {
      try {
        await s.cancel();
      } catch (e) {
        debugPrint('BLE: falha ignorada: $e');
      }
    }
    _connSubs.clear();
    final device = _connectedDevice;
    _connectedDevice = null;
    if (device != null) {
      try {
        await device.disconnect().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Já desconectado ou sem resposta: o app segue como desconectado.
      }
    }
    _reqDataChar = null;
    _assetTrackTxChar = null;
    _bulkTxChar = null;
    _rxChar = null;
    _isConnected = false;
  }
}

/// Cabeçalho confirmado de um bloco de evento SCS (16 bytes).
/// Os 6 bytes finais do bloco de 16 não são usados pelo parser oficial
/// (reservado/alinhamento).
class EventBlockHeader {
  final int rawTimestamp; // segundos, época a confirmar (provável Unix epoch)
  final int status;
  final int protocolVersion;
  final int reserved;

  const EventBlockHeader({
    required this.rawTimestamp,
    required this.status,
    required this.protocolVersion,
    required this.reserved,
  });
}

/// Telemetria ao vivo decodificada do anúncio BLE (sem conexão/auth).
class LiveTelemetry {
  /// Id BLE do sensor (chave da lista multi-sensor).
  final String deviceId;

  final DateTime at;

  /// Temperatura em °C, ou null se o payload ainda não decodificou.
  final double? temperatureC;

  final int rssi;

  /// Nome/serial do asset anunciado (ASCII após a temperatura).
  final String assetName;

  /// Bytes 0-1 do payload (candidatos a flags de status/porta). O bit de
  /// porta aberta ainda NÃO foi confirmado no hardware — a tela mostra estes
  /// bytes em binário pra identificar qual muda ao abrir a porta.
  final List<int> flagBytes;

  final String rawHex;

  const LiveTelemetry({
    required this.deviceId,
    required this.at,
    required this.temperatureC,
    required this.rssi,
    required this.assetName,
    required this.flagBytes,
    required this.rawHex,
  });
}

/// Uma amostra do payload de fabricante (0x578) do anúncio BLE.
class _AdvSample {
  final DateTime at;
  final String hex;
  final List<int> bytes;
  const _AdvSample(this.at, this.hex, this.bytes);
}

/// Resultado estruturado do download de páginas da memória flash interna SCS.
class FlashDownloadResult {
  final String deviceId;
  final int sensorTimestamp;
  final int offsetSeconds;
  final bool usedFastMode;
  final int blockCount;
  final int protocolVersion;
  final int? firstBlockStatus;
  final List<SensorReading> readings;
  final List<String> diagnosticLines;

  const FlashDownloadResult({
    required this.deviceId,
    required this.sensorTimestamp,
    required this.offsetSeconds,
    required this.usedFastMode,
    required this.blockCount,
    required this.protocolVersion,
    this.firstBlockStatus,
    required this.readings,
    required this.diagnosticLines,
  });
}

/// Dispositivo BLE encontrado no scan (nome anunciado + sinal).
class DiscoveredDevice {
  final String id;
  final String name;
  final int rssi;
  const DiscoveredDevice({required this.id, required this.name, required this.rssi});
}
