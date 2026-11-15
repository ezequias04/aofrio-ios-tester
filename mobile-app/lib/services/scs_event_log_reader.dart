import 'dart:async';
import 'dart:typed_data';

import 'scs_stats_decoder.dart';

/// Leitor do log de eventos (páginas de 1024 B) do Monitor, port do protocolo do
/// app oficial SCS Field (`BluetoothLeCommsService`: §_-Ef§, §_-6z§, §_-87§,
/// §_-51§, §_-G1§, §_-CC§, §_-Cl§).
///
/// Canais BLE (serviço SCS Asset Track 1DECA38D-…):
///   - REQ_DATA  D224EEED-…  recebe o pedido de start-address (cmd 5).
///   - RX        0D3DE66C-…  recebe pedidos de leitura de memória (cmd 1 ou 3).
///   - TX        EFDD2460-…  respostas de cmd 5 e chunks no modo normal.
///   - BULK TX   FFDD2460-…  chunks no modo rápido.
///
/// Chunk de resposta: [dummy u8][endereço u16 LE][len u8][16 bytes de dados].
/// Com protocolVersion >= 18, endereço += (len & 3) << 16.

const int kChunkSize = 16;
const int kCmdReadFast = 1;
const int kCmdReadDirect = 3;
const int kCmdEventStartAddress = 5;
const int kProtocolVersionAddressHigh = 18;
const int _kInvalidTimestamp = 0xFFFFFFFF;

/// Pedido de start-address: [5, horaInicio u16] (horaInicio em segundos do sensor).
Uint8List buildStartAddressRequest(int reqTimeSecs) {
  final t = reqTimeSecs.clamp(0, 0xFFFF).toInt();
  return Uint8List.fromList([kCmdEventStartAddress, t & 0xFF, (t >> 8) & 0xFF]);
}

/// Leitura direta de um chunk (cmd 3). Sempre 16 bytes nesta implementação.
Uint8List buildReadDirect(int address, int protocolVersion) {
  final b = <int>[kCmdReadDirect, address & 0xFF, (address >> 8) & 0xFF];
  if (protocolVersion < kProtocolVersionAddressHigh) {
    b.add(kChunkSize & 0xFF);
  } else {
    b.add((((address >> 16) & 3) + (kChunkSize << 2)) & 0xFF);
  }
  return Uint8List.fromList(b);
}

/// Leitura rápida de um intervalo (cmd 1): [1, início u32, fim u32, 15|10, 0].
/// 15 no Windows nativo, 10 nos demais (valor usado pelo app oficial).
Uint8List buildReadFast(int address, int length, {required bool windowsNative}) {
  final bd = ByteData(11);
  bd.setUint8(0, kCmdReadFast);
  bd.setUint32(1, address, Endian.little);
  bd.setUint32(5, address + length, Endian.little);
  bd.setUint8(9, windowsNative ? 15 : 10);
  bd.setUint8(10, 0);
  return bd.buffer.asUint8List();
}

class ChunkResponse {
  final int address;
  final Uint8List data;
  const ChunkResponse(this.address, this.data);
}

/// Interpreta um chunk de 20 bytes. Retorna null se o tamanho não bate.
ChunkResponse? parseChunk(Uint8List n, int protocolVersion) {
  if (n.length < 4 + kChunkSize) return null;
  var address = n[1] | (n[2] << 8);
  if (protocolVersion >= kProtocolVersionAddressHigh) {
    address += (n[3] & 3) << 16;
  }
  return ChunkResponse(address, Uint8List.sublistView(n, 4, 4 + kChunkSize));
}

class StartAddressResponse {
  final int startAddress;
  final int count;
  final int blockSize;
  const StartAddressResponse(this.startAddress, this.count, this.blockSize);
}

/// Resposta do cmd 5: [5, startAddress u16, count u16, blockSize u16].
StartAddressResponse? parseStartAddressResponse(Uint8List n) {
  if (n.length < 7 || n[0] != kCmdEventStartAddress) return null;
  final bd = ByteData.sublistView(n);
  return StartAddressResponse(
    bd.getUint16(1, Endian.little),
    bd.getUint16(3, Endian.little),
    bd.getUint16(5, Endian.little),
  );
}

/// Fila de notificações: guarda o que chega antes de alguém esperar.
class _Inbox {
  final List<Uint8List> _items = [];
  Completer<void>? _waiter;

  void add(Uint8List b) {
    _items.add(b);
    final w = _waiter;
    _waiter = null;
    w?.complete();
  }

  /// Próxima notificação que satisfaz [match], descartando as outras.
  Future<T> next<T>(Duration timeout, T? Function(Uint8List) match) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      while (_items.isNotEmpty) {
        final r = match(_items.removeAt(0));
        if (r != null) return r;
      }
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) throw TimeoutException('sem resposta do sensor');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(left);
    }
  }

  void clear() => _items.clear();
}

typedef BleWrite = Future<void> Function(Uint8List bytes);

class ScsEventLogReader {
  ScsEventLogReader({
    required this.writeReqData,
    required this.writeRx,
    required Stream<Uint8List> tx,
    required Stream<Uint8List> bulk,
    required this.protocolVersion,
    required this.fastRead,
    this.windowsNative = false,
    this.timeout = const Duration(seconds: 3),
  }) {
    _txSub = tx.listen(_tx.add);
    _bulkSub = bulk.listen(_bulk.add);
  }

  final BleWrite writeReqData;
  final BleWrite writeRx;
  final int protocolVersion;
  final bool fastRead; // modo rápido (chunks no canal BULK) ou um chunk por pedido
  final bool windowsNative;
  final Duration timeout;

  final _tx = _Inbox();
  final _bulk = _Inbox();
  StreamSubscription<Uint8List>? _txSub;
  StreamSubscription<Uint8List>? _bulkSub;

  Future<void> dispose() async {
    await _txSub?.cancel();
    await _bulkSub?.cancel();
  }

  /// Lê todas as páginas a partir de [reqTimeSecs] (relógio do sensor) e devolve
  /// as que passaram na checagem de timestamp, ordenadas como no original.
  Future<List<ScsEventBlock>> readEventLog({required int reqTimeSecs}) async {
    _tx.clear();
    _bulk.clear();
    await writeReqData(buildStartAddressRequest(reqTimeSecs));
    final start = await _tx.next(timeout, parseStartAddressResponse);
    if (start.count == 0) return const [];

    final blockSize = start.blockSize == 0 ? 1024 : start.blockSize;
    final blocks = <ScsEventBlock>[];
    for (var i = 0; i < start.count; i++) {
      final addr = start.startAddress + i * blockSize;
      final header = await _readRange(addr, kChunkSize, fast: false);
      final hdr = ByteData.sublistView(header);
      final status = hdr.getUint16(4, Endian.little);
      final rawTs = hdr.getUint32(0, Endian.little);
      // Mesmo filtro do original: descarta vazio/inválido.
      if (rawTs == _kInvalidTimestamp || !_isUsefulStatus(status)) continue;

      final rest = await _readRange(addr + kChunkSize, blockSize - kChunkSize,
          fast: fastRead);
      // Verificação: se o cabeçalho mudou durante a leitura, o bloco é descartado.
      final again = await _readRange(addr, kChunkSize, fast: false);
      if (ByteData.sublistView(again).getUint32(0, Endian.little) != rawTs) {
        continue;
      }
      final page = Uint8List(blockSize)
        ..setRange(0, kChunkSize, header)
        ..setRange(kChunkSize, blockSize, rest);
      blocks.add(ScsEventBlock.fromPage(addr, page));
    }
    blocks.sort((a, b) {
      final c = a.rawTimestamp.compareTo(b.rawTimestamp);
      return c != 0 ? c : a.status.compareTo(b.status);
    });
    return blocks;
  }

  static bool _isUsefulStatus(int s) =>
      s == 0xFF00 || s == 0x0000 || s == 0xAAAA || s == 0xAAAB;

  /// Lê [length] bytes a partir de [address]. Modo rápido: um pedido e chunks em
  /// sequência no canal BULK. Modo normal: um chunk de 16 por pedido.
  Future<Uint8List> _readRange(int address, int length, {required bool fast}) async {
    final out = Uint8List(length);
    if (fast && length > kChunkSize) {
      await writeRx(buildReadFast(address, length, windowsNative: windowsNative));
      for (var off = 0; off < length; off += kChunkSize) {
        final want = address + off;
        final c = await _bulk.next(timeout, (n) {
          final r = parseChunk(n, protocolVersion);
          return (r != null && r.address == want) ? r : null;
        });
        out.setRange(off, off + kChunkSize, c.data);
      }
    } else {
      for (var off = 0; off < length; off += kChunkSize) {
        final want = address + off;
        await writeRx(buildReadDirect(want, protocolVersion));
        final c = await _tx.next(timeout, (n) {
          final r = parseChunk(n, protocolVersion);
          return (r != null && r.address == want) ? r : null;
        });
        out.setRange(off, off + kChunkSize, c.data);
      }
    }
    return out;
  }
}
