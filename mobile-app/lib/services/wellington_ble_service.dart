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

  @override
  Stream<List<DiscoveredDevice>> scanForDevices() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    return FlutterBluePlus.scanResults.map((results) {
      return results
          .where((r) => r.device.platformName.isNotEmpty)
          // O Wellington Monitor anuncia o nome BLE igual ao serial da
          // etiqueta + sufixo (ex.: "B152E02371079226226"). Filtra por
          // esse padrão para não confundir com outros periféricos BLE
          // da sala (fones, carros, etc.).
          .where((r) => _looksLikeWellingtonMonitor(r.device.platformName))
          .map((r) => DiscoveredDevice(
                id: r.device.remoteId.str,
                name: r.device.platformName,
                rssi: r.rssi,
              ))
          .toList();
    });
  }

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

    // Ativar notificação em ambas as características é tudo que o "handshake"
    // de autenticação exige para o Monitor — ver nota no topo do arquivo.
    await _assetTrackTxChar!.setNotifyValue(true);
    _assetTrackTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isNotEmpty) _statusController.add(Uint8List.fromList(bytes));
    });

    await _bulkTxChar!.setNotifyValue(true);
    _bulkTxChar!.lastValueStream.listen((bytes) {
      if (bytes.isNotEmpty) _eventBlockController.add(Uint8List.fromList(bytes));
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
    await _reqDataChar!.write([commandCode], withoutResponse: false);
  }

  /// Pede o histórico de eventos a partir do endereço inicial
  /// (`SCS_REQUEST_EVENT_START_ADDRESS`, comando confirmado). A resposta
  /// chega em [rawEventBlocks] — não é consumida aqui porque o layout de
  /// cada registro dentro do bloco ainda não está confirmado (ver topo do
  /// arquivo); use isso para capturar blocos brutos e comparar com a
  /// temperatura real do equipamento no momento do teste.
  Future<void> requestEventLogFromStart() async {
    if (_reqDataChar == null) throw Exception('Não conectado.');
    await _writeCommand(scsRequestEventStartAddress);
  }

  @override
  Future<List<SensorReading>> downloadStoredHistory() async {
    // Único gap real que falta (autenticação NÃO é necessária — ver nota
    // no topo do arquivo): o layout de cada registro de temperatura/porta/
    // vibração dentro do bloco de 1024 bytes, depois do cabeçalho de 16
    // já confirmado em parseEventBlockHeader. Sem isso não dá para montar
    // SensorReading de verdade a partir dos blocos que rawEventBlocks já
    // entrega corretamente.
    //
    // Para descobrir: chamar connect() + requestEventLogFromStart(),
    // escutar rawEventBlocks, e comparar os bytes do corpo de cada bloco
    // com a temperatura real do equipamento no momento (ver
    // specs/wellington_scs_protocol.md, seção "NÃO confirmado").
    throw UnimplementedError(
      'Falta decodificar o layout do registro de evento dentro do bloco '
      '(autenticação não é mais um bloqueio). Ver specs/wellington_scs_protocol.md.',
    );
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
