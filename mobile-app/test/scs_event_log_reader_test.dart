import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aofrio_test_app/services/scs_event_log_reader.dart';
import 'package:aofrio_test_app/services/scs_stats_decoder.dart';

/// Sensor falso: responde aos mesmos comandos do Monitor real (cmd 5 na REQ_DATA,
/// cmd 3 e cmd 1 no RX). Respostas normais vão pelo canal TX, rápidas pelo BULK.
class FakeSensor {
  FakeSensor(this.mem, {this.start = 0x1000, this.blockSize = 1024, this.count = 1});

  final Uint8List mem;
  final int start;
  final int blockSize;
  final int count;
  final tx = StreamController<Uint8List>.broadcast();
  final bulk = StreamController<Uint8List>.broadcast();

  Future<void> writeReqData(Uint8List b) async {
    if (b[0] != 5) return;
    final bd = ByteData(7)
      ..setUint8(0, 5)
      ..setUint16(1, start, Endian.little)
      ..setUint16(3, count, Endian.little)
      ..setUint16(5, blockSize, Endian.little);
    tx.add(bd.buffer.asUint8List());
  }

  Future<void> writeRx(Uint8List b) async {
    if (b[0] == 3) {
      tx.add(_chunk(b[1] | (b[2] << 8)));
    } else if (b[0] == 1) {
      final bd = ByteData.sublistView(b);
      final from = bd.getUint32(1, Endian.little);
      final to = bd.getUint32(5, Endian.little);
      for (var a = from; a < to; a += kChunkSize) {
        bulk.add(_chunk(a));
      }
    }
  }

  Uint8List _chunk(int addr) {
    final out = Uint8List(20);
    out[0] = 0; // dummy
    out[1] = addr & 0xFF;
    out[2] = (addr >> 8) & 0xFF;
    out[3] = 64; // (len << 2) com len = 16
    out.setRange(4, 20, mem.sublist(addr - start, addr - start + kChunkSize));
    return out;
  }
}

/// Página não comprimida (BUFFER1): header + tag 8 (temp1Ave) = [8,1,40,0].
Uint8List buildPage() {
  final p = Uint8List(1024);
  final bd = ByteData.sublistView(p);
  bd.setUint32(0, 1000, Endian.little); // rawTimestamp
  bd.setUint16(4, 0xAAAA, Endian.little); // BUFFER1
  bd.setUint16(6, 70, Endian.little); // protocolVersion
  p.setRange(16, 20, [8, 1, 40, 0]);
  return p;
}

void main() {
  test('pedido de start-address: [5, hora u16]', () {
    expect(buildStartAddressRequest(0x0102), [5, 0x02, 0x01]);
  });

  test('cmd 3 (pv >= 18) carrega bits altos do endereço e len<<2', () {
    expect(buildReadDirect(0x1000, 70), [3, 0x00, 0x10, 64]);
  });

  test('chunk: endereço com bits altos (pv >= 18)', () {
    final n = Uint8List.fromList([0, 0x34, 0x12, 0x01, ...List.filled(16, 7)]);
    final r = parseChunk(n, 70);
    expect(r!.address, 0x10000 + 0x1234);
    expect(r.data.first, 7);
  });

  for (final fast in [false, true]) {
    test('leitor (fastRead=$fast): lê página e decodifica temp 11.8 °C', () async {
      final sensor = FakeSensor(buildPage());
      final reader = ScsEventLogReader(
        writeReqData: sensor.writeReqData,
        writeRx: sensor.writeRx,
        tx: sensor.tx.stream,
        bulk: sensor.bulk.stream,
        protocolVersion: 70,
        fastRead: fast,
        timeout: const Duration(seconds: 2),
      );
      final blocks = await reader.readEventLog(reqTimeSecs: 0);
      await reader.dispose();

      expect(blocks.length, 1);
      final readings = decodeStatsV2(
        blocks: blocks,
        sensorToUnixOffsetSecs: 0,
        protocolVersion: 70,
      );
      expect(readings.length, 1);
      expect(readings.first.temperature, closeTo(11.8, 0.001));
      expect(readings.first.timestamp.millisecondsSinceEpoch, 1000 * 1000);
    });
  }
}
