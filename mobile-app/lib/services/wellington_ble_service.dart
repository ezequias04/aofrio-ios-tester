import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';
import 'ble_service_interface.dart';

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
class WellingtonBleService implements IBleService {
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

  @override
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

  @override
  Stream<List<DiscoveredDevice>> scanForDevices() async* {
    // No iOS o adaptador começa em "unknown"; escanear antes de "on" não acha nada.
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw Exception('Bluetooth desligado ou sem permissão. Ative o Bluetooth e '
          'permita o acesso em Ajustes > AoFrio Test.');
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

  /// Desconecta e fica ouvindo o anúncio do sensor por [duration], juntando
  /// payloads distintos do fabricante 0x578. Chamado quando o histórico via
  /// conexão não vem — para fechar o campo de temperatura livre de auth.
  Future<void> _watchAdvertisementTemperature(Duration duration) async {
    final id = _connectedDevice?.remoteId.str;
    if (id == null) return;
    _log('ADV_WATCH desconectando para ouvir anúncio por ${duration.inSeconds}s…');
    _advSamples.remove(id);
    try {
      await _connectedDevice!.disconnect();
    } catch (_) {}
    try {
      await FlutterBluePlus.startScan(timeout: duration, androidUsesFineLocation: false);
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.device.remoteId.str != id) continue;
          final w = r.advertisementData.manufacturerData[0x578];
          if (w == null) continue;
          final hex = w.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          final list = _advSamples.putIfAbsent(id, () => []);
          if ((list.isEmpty || list.last.hex != hex) && list.length < 60) {
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

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<bool> connect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
    _connectedDevice = device;

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
            c.onValueReceived.listen((v) => _log('NOTIF $s8/$c8', v));
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
    _assetTrackTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      _log('TX', bytes);
      _statusController.add(Uint8List.fromList(bytes));
    });

    _log('NOTIFY BULK ffdd2460 -> ${await _bulkTxChar!.setNotifyValue(true)}');
    _bulkTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      _log('BULK', bytes);
      _eventBlockController.add(Uint8List.fromList(bytes));
    });

    _isConnected = true;
    return true;
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

  @override
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
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      _log('FIM comandos: ${receivedBlocks.length} blocos BULK, nada decodificado');
      // Caminho sem autenticação: ouvir o anúncio BLE por 20s e decodificar
      // o campo de temperatura que o sensor transmite para gateways.
      await _watchAdvertisementTemperature(const Duration(seconds: 20));
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
    } catch (_) {}

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

  @override
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _reqDataChar = null;
    _assetTrackTxChar = null;
    _bulkTxChar = null;
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

/// Uma amostra do payload de fabricante (0x578) do anúncio BLE.
class _AdvSample {
  final DateTime at;
  final String hex;
  final List<int> bytes;
  const _AdvSample(this.at, this.hex, this.bytes);
}
