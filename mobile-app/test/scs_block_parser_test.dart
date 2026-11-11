import 'dart:typed_data';

import 'package:aofrio_test_app/services/wellington_ble_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodifica cabeçalho de 16 bytes e registros 16-bit LE (0.1°C + flag de porta)', () {
    final bd = ByteData(16 + 6);
    bd.setUint32(0, 1794300000, Endian.little); // timestamp
    bd.setUint16(4, 0x0003, Endian.little); // status
    bd.setUint16(6, 0x0102, Endian.little); // versão
    bd.setInt16(16, 253, Endian.little); // 25.3°C
    bd.setInt16(18, -15, Endian.little); // -1.5°C
    bd.setUint16(20, 0x8000 | 87, Endian.little); // 8.7°C, porta aberta
    final block = bd.buffer.asUint8List();

    final header = WellingtonBleService.parseEventBlockHeader(block);
    expect(header.rawTimestamp, 1794300000);
    expect(header.status, 3);
    expect(header.protocolVersion, 0x0102);

    final readings = WellingtonBleService.parseBlockRecords(block);
    expect(readings.map((r) => r.temperature), [25.3, -1.5, 8.7]);
    expect(readings.map((r) => r.doorOpen), [false, false, true]);
    expect(readings[1].timestamp.difference(readings[0].timestamp).inMinutes, 1);
  });

  test('bloco menor que o cabeçalho não gera leituras', () {
    expect(WellingtonBleService.parseBlockRecords(Uint8List(8)), isEmpty);
  });
}
