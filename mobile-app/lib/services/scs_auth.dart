import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

/// Implementação fiel do handshake de autenticação SCS (`ScsAuth`, `CRC32` e
/// `OtaDataConvert` do bytecode de `Main.swf` no app oficial SCS Field).
///
/// Sem este handshake na característica `SCS_AUTH_CHARACTERISTIC`
/// (`34d81c0d-a398-4828-b702-8b7f42f5bf96`) e leitura em
/// `SCS_AUTH_RESPONSE_CHARACTERISTIC` (`673ebc29-fb79-4fbb-8b86-c3255a12f784`),
/// o sensor Wellington Monitor recusa ou ignora qualquer comando em
/// `SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC` e `SCS_ASSET_TRACK_RX_CHARACTERISTIC`.

/// Chave padrão RC4 de handshake (`244ca7859354d10a9f48901ebf656caa`) extraída
/// do método `ScsAuth.onScsResponse` (linha 741 do bytecode).
final Uint8List kDefaultScsAuthKey = Uint8List.fromList(const [
  0x24, 0x4c, 0xa7, 0x85, 0x93, 0x54, 0xd1, 0x0a,
  0x9f, 0x48, 0x90, 0x1e, 0xbf, 0x65, 0x6c, 0xaa,
]);

/// CRC32 idêntico à classe `com.wdtl.scs.diagnostic.util.CRC32` do app oficial.
/// Nota: no original, `ScsAuth` faz `~crc32.getValue()` após `update`, o que
/// cancela a inversão final do CRC32 padrão.
int scsCrc32Hash(int challengeU32) {
  final bd = ByteData(4)..setUint32(0, challengeU32, Endian.little);
  final bytes = bd.buffer.asUint8List();
  int c = 0xFFFFFFFF;
  for (int i = 0; i < bytes.length; i++) {
    int idx = (c ^ bytes[i]) & 0xFF;
    int entry = idx;
    for (int bit = 8; bit >= 0; bit--) {
      if ((entry & 1) != 0) {
        entry = (0xEDB88320 ^ (entry >>> 1)) & 0xFFFFFFFF;
      } else {
        entry = (entry >>> 1) & 0xFFFFFFFF;
      }
    }
    c = (entry ^ (c >>> 8)) & 0xFFFFFFFF;
  }
  final crcValue = (~c) & 0xFFFFFFFF;
  return (~crcValue) & 0xFFFFFFFF;
}

/// Cifra de fluxo RC4 idêntica a `com.wdtl.scs.diagnostic.util.OtaDataConvert`.
/// Cada chamada a [transformInPlace] reinicializa o estado S[0..255] com a
/// chave [key] antes de fazer XOR byte a byte (comportamento exato de
/// `OtaDataConvert.dataIn` / `dataOut`).
class ScsOtaCipher {
  Uint8List _key;
  final Uint8List _s = Uint8List(256);
  int _i = 0;
  int _j = 0;

  ScsOtaCipher(Uint8List key) : _key = Uint8List.fromList(key) {
    init(_key);
  }

  void init(Uint8List key) {
    _key = Uint8List.fromList(key);
    for (int k = 0; k < 256; k++) {
      _s[k] = k;
    }
    int j = 0;
    for (int k = 0; k < 256; k++) {
      j = (j + _s[k] + _key[k % _key.length]) & 0xFF;
      final tmp = _s[k];
      _s[k] = _s[j];
      _s[j] = tmp;
    }
    _i = 0;
    _j = 0;
  }

  int _next() {
    _i = (_i + 1) & 0xFF;
    _j = (_j + _s[_i]) & 0xFF;
    final tmp = _s[_i];
    _s[_i] = _s[_j];
    _s[_j] = tmp;
    return _s[(tmp + _s[_i]) & 0xFF];
  }

  void transformInPlace(Uint8List data) {
    init(_key);
    for (int k = 0; k < data.length; k++) {
      data[k] ^= _next();
    }
  }
}

/// Resultado do handshake de autenticação SCS com metadados reais do sensor.
class ScsAuthResult {
  final int hashType;
  final int authStatus;
  final int protocolVersion;
  final int controllerCodeRevision;
  final int otaCodeRevision;
  final int highSideCodeRevision;
  final int productId;
  final int productRevision;
  final int betaVersion;
  final int controllerCodeSubRevision;
  final int hardwareId;
  final bool isEncryptedSession;
  final ScsOtaCipher? sessionCipher;

  const ScsAuthResult({
    required this.hashType,
    required this.authStatus,
    required this.protocolVersion,
    required this.controllerCodeRevision,
    required this.otaCodeRevision,
    required this.highSideCodeRevision,
    required this.productId,
    required this.productRevision,
    required this.betaVersion,
    required this.controllerCodeSubRevision,
    required this.hardwareId,
    required this.isEncryptedSession,
    this.sessionCipher,
  });

  /// Mesma regra de `BluetoothLeCommsService.onSetNotificationSuccess`:
  /// `(productId == 1 && protocolVersion >= 30) || (productId == 16 && controllerCodeRevision >= 4)`
  bool get supportsFastEventBlockRead =>
      (productId == 1 && protocolVersion >= 30) ||
      (productId == 16 && controllerCodeRevision >= 4);

  /// Mesma regra de `BluetoothLeCommsService.productReportsBlockSize`:
  /// `(productId == 1 && protocolVersion >= 30) || productId == 16`
  bool get reportsBlockSize =>
      (productId == 1 && protocolVersion >= 30) || productId == 16;

  /// Criptografa ou descriptografa um pacote de Asset Track quando a sessão
  /// usa criptografia de tipo 2/3 (`isTypeTwoOrThreeConnection`).
  Uint8List transformPacket(Uint8List bytes) {
    if (!isEncryptedSession || sessionCipher == null) return bytes;
    final copy = Uint8List.fromList(bytes);
    sessionCipher!.transformInPlace(copy);
    return copy;
  }
}

/// Pacote inicial de 11 bytes de `ScsAuth.start`:
/// `[1, 0, 0, 0, 0, 0, 0, keyLevel(2), 0, 7, 0]`
Uint8List buildScsAuthStartPacket({int keyLevel = 2}) {
  return Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, keyLevel & 0xFF, 0, 7, 0]);
}

/// Calcula a resposta de 32 bits ao desafio (`challengeU32`) conforme `hashType`:
/// - `0`: retorna `challengeU32` direto
/// - `1` (`HASH_TYPE_CRC32`): `scsCrc32Hash(challengeU32)`
/// - `2` (`HASH_TYPE_2`): deriva chave RC4 e cifra `challengeU32`
({int responseU32, ScsOtaCipher? cipher, bool isTypeTwoOrThree})
    computeScsChallengeResponse({
  required int hashType,
  required int challengeU32,
  Uint8List? customKey,
}) {
  if (hashType == 0) {
    return (
      responseU32: challengeU32 & 0xFFFFFFFF,
      cipher: null,
      isTypeTwoOrThree: false,
    );
  }
  if (hashType == 1) {
    return (
      responseU32: scsCrc32Hash(challengeU32),
      cipher: null,
      isTypeTwoOrThree: false,
    );
  }
  if (hashType == 2) {
    final key = Uint8List.fromList(customKey ?? kDefaultScsAuthKey);
    final cipher = ScsOtaCipher(key);
    // ScsAuth.onScsResponse linhas 461-498:
    // cipher.init(key); cipher.dataIn(key); cipher.init(key);
    cipher.transformInPlace(key);
    cipher.init(key);

    final bd = ByteData(4)..setUint32(0, challengeU32, Endian.little);
    final chalBytes = bd.buffer.asUint8List();
    cipher.transformInPlace(chalBytes);
    final resp = ByteData.sublistView(chalBytes).getUint32(0, Endian.little);
    return (
      responseU32: resp,
      cipher: cipher,
      isTypeTwoOrThree: false,
    );
  }
  throw Exception('Tipo de desafio SCS não suportado: hashType=$hashType');
}

/// Monta o pacote de 9 bytes do Passo 2 de `ScsAuth`:
/// `[2, respU32 LE (4B), minConnInterval u16 LE, maxConnInterval u16 LE]`
/// No Android SDK >= 23: (9, 10). No iOS: (12, 12).
Uint8List buildScsAuthChallengeResponsePacket({
  required int responseU32,
  required bool isIos,
}) {
  final minConn = isIos ? 12 : 9;
  final maxConn = isIos ? 12 : 10;
  final bd = ByteData(9)
    ..setUint8(0, 2)
    ..setUint32(1, responseU32, Endian.little)
    ..setUint16(5, minConn, Endian.little)
    ..setUint16(7, maxConn, Endian.little);
  return bd.buffer.asUint8List();
}

/// Exponenciação modular `base^exp mod modulus` idêntica a `ScsAuth._-HQ`.
int _modPow(int base, int exp, int modulus) {
  return BigInt.from(base).modPow(BigInt.from(exp), BigInt.from(modulus)).toInt();
}

/// Executa o handshake completo `ScsAuth` com o sensor.
///
/// [writeAuth]: escreve em `SCS_AUTH_CHARACTERISTIC` (`34d81c0d-…`).
/// [readAuthResponse]: lê `SCS_AUTH_RESPONSE_CHARACTERISTIC` (`673ebc29-…`).
/// [authNotifications]: opcional, stream de notificações de `673ebc29-…` caso o
/// sensor notifique antes dos 250 ms.
Future<ScsAuthResult> performScsAuthentication({
  required Future<void> Function(Uint8List bytes) writeAuth,
  required Future<Uint8List> Function() readAuthResponse,
  Stream<Uint8List>? authNotifications,
  bool isIos = false,
  Duration stepDelay = const Duration(milliseconds: 250),
}) async {
  /// Espera a resposta do sensor. O app oficial lê uma vez após 250 ms; aqui
  /// repetimos a leitura (até ~3 s) até chegar um pacote cujo primeiro byte é o
  /// comando esperado, para não aceitar a resposta velha do passo anterior.
  Future<Uint8List> waitResp(int expectedFirstByte) async {
    Completer<Uint8List>? notifCompleter;
    StreamSubscription<Uint8List>? sub;
    if (authNotifications != null) {
      notifCompleter = Completer<Uint8List>();
      sub = authNotifications.listen((data) {
        if (data.isNotEmpty &&
            data[0] == expectedFirstByte &&
            !notifCompleter!.isCompleted) {
          notifCompleter.complete(data);
        }
      });
    }
    try {
      Uint8List last = Uint8List(0);
      for (var attempt = 0; attempt < 12; attempt++) {
        await Future<void>.delayed(stepDelay);
        if (notifCompleter != null && notifCompleter.isCompleted) {
          return await notifCompleter.future;
        }
        last = await readAuthResponse();
        if (last.isNotEmpty && last[0] == expectedFirstByte) return last;
        if (stepDelay == Duration.zero) break; // testes: sem repetição
      }
      return last;
    } finally {
      await sub?.cancel();
    }
  }

  // Passo 1: Envia [1, 0, 0, 0, 0, 0, 0, 2, 0, 7, 0] e lê o desafio após 250ms
  await writeAuth(buildScsAuthStartPacket());
  final step1 = await waitResp(1);
  if (step1.length < 6) {
    throw Exception(
      'Resposta de autenticação SCS curta demais no passo 1 (${step1.length} B).',
    );
  }
  final bd1 = ByteData.sublistView(step1);
  final hashType = bd1.getInt8(1);
  final challenge = bd1.getUint32(2, Endian.little);

  if (hashType == 3) {
    throw Exception('Protocolo SCS tipo 3 não reconhecido pelo sensor.');
  }

  final calc = computeScsChallengeResponse(
    hashType: hashType,
    challengeU32: challenge,
  );

  // Passo 2: Envia [2, responseU32, minInterval, maxInterval] e lê resultado após 250ms
  final pkt2 = buildScsAuthChallengeResponsePacket(
    responseU32: calc.responseU32,
    isIos: isIos,
  );
  await writeAuth(pkt2);
  final step2 = await waitResp(2);
  if (step2.length < 13) {
    throw Exception(
      'Resposta de autenticação SCS curta demais no passo 2 (${step2.length} B).',
    );
  }

  final bd2 = ByteData.sublistView(step2);
  final cmdEcho = bd2.getInt8(0);
  if (cmdEcho != 2) {
    throw Exception('Handshake SCS recusado (código $cmdEcho).');
  }
  // offset 1..2: uint16 ignorado; offset 3..4: authStatus uint16
  final authStatus = bd2.getUint16(3, Endian.little);
  switch (authStatus) {
    case 0:
    case 2:
      break; // Sucesso!
    case 1:
      throw Exception('Sensor em espera de segurança (holdoff ativo). Aguarde e tente novamente.');
    case 3:
      throw Exception('Sinal fraco demais para autenticar. Aproxime o celular do sensor.');
    case 4:
      throw Exception('O sensor exigiu pressionar o botão físico.');
    default:
      throw Exception('Falha de autenticação SCS (status=$authStatus).');
  }

  final protocolVersion = bd2.getUint16(5, Endian.little);
  final controllerCodeRevision = bd2.getUint16(7, Endian.little);
  final otaCodeRevision = bd2.getUint16(9, Endian.little);
  final highSideCodeRevision = bd2.getUint16(11, Endian.little);

  int pos = 13;
  int productId = 16; // Monitor padrão
  int productRevision = 0;
  if ((protocolVersion >= 12 || hashType == 2) && step2.length >= pos + 2) {
    final prodRaw = bd2.getUint16(pos, Endian.little);
    pos += 2;
    // Globals: PRODUCT_ID_AND_REV_SCS_MONITOR = 4097 = 0x1001
    //   -> byte ALTO = productId (0x10 = 16 = Monitor), byte baixo = revisão.
    productId = (prodRaw >> 8) & 0xFF;
    productRevision = prodRaw & 0xFF;
  }

  int betaVersion = 0;
  int subRevision = 0;
  int hardwareId = 0;
  bool extraFlag = false;

  if ((protocolVersion >= 15 || hashType == 2) && step2.length >= pos + 2) {
    final subRaw = bd2.getUint16(pos, Endian.little);
    pos += 2;
    betaVersion = (subRaw >> 8) & 0xFF;
    subRevision = subRaw & 0xFF;
    if (protocolVersion >= 20) {
      if (step2.length >= pos + 1) {
        hardwareId = step2[pos++];
      }
      if (step2.length >= pos + 1) {
        final flagByte = step2[pos++];
        extraFlag = (hashType == 2 && flagByte == 1);
      }
    }
  }

  // Passo opcional DH (quando isTypeTwoOrThreeConnection || extraFlag)
  var sessionCipher = calc.cipher;
  // Original: isTypeTwoOrThreeConnection && flag. Para o Monitor (hash tipo 2)
  // isTypeTwoOrThreeConnection é sempre falso -> sem troca de chaves.
  final needKeyExchange = calc.isTypeTwoOrThree && extraFlag;
  if (needKeyExchange && sessionCipher != null) {
    const prime = 2147483647;
    const generator = 5;
    final rng = Random.secure();
    final exponents = List<int>.generate(4, (_) => rng.nextInt(65536));
    final pkt3 = ByteData(17)..setUint8(0, 4);
    for (int i = 0; i < 4; i++) {
      final pub = _modPow(generator, exponents[i], prime);
      pkt3.setUint32(1 + i * 4, pub, Endian.little);
    }
    await writeAuth(pkt3.buffer.asUint8List());
    final step3 = await waitResp(4);
    if (step3.length >= 17) {
      final bd3 = ByteData.sublistView(step3);
      final sharedKey = ByteData(16);
      for (int i = 0; i < 4; i++) {
        final peerPub = bd3.getUint32(1 + i * 4, Endian.little);
        final secret = _modPow(peerPub, exponents[i], prime);
        sharedKey.setUint32(i * 4, secret, Endian.little);
      }
      final keyBytes = sharedKey.buffer.asUint8List();
      sessionCipher.init(keyBytes);
      if (hashType == 2) {
        sessionCipher.transformInPlace(keyBytes);
        sessionCipher.init(keyBytes);
      }
    }
  }

  return ScsAuthResult(
    hashType: hashType,
    authStatus: authStatus,
    protocolVersion: protocolVersion,
    controllerCodeRevision: controllerCodeRevision,
    otaCodeRevision: otaCodeRevision,
    highSideCodeRevision: highSideCodeRevision,
    productId: productId,
    productRevision: productRevision,
    betaVersion: betaVersion,
    controllerCodeSubRevision: subRevision,
    hardwareId: hardwareId,
    isEncryptedSession: calc.isTypeTwoOrThree,
    sessionCipher: sessionCipher,
  );
}
