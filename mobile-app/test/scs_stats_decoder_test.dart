import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aofrio_test_app/services/scs_stats_decoder.dart';

void main() {
  test('CRC-16/CCITT-FALSE bate com o valor de referência', () {
    final bytes = Uint8List.fromList(ascii.encode('123456789'));
    expect(crc16(bytes, 0, bytes.length), 0x29B1);
  });

  test('frame ACTIVE LZSS: literais 08 01 28 00 viram temp1Ave 11.8 °C', () {
    // Literais LZSS (flag 1 + 8 bits cada), 36 bits -> 5 bytes:
    // 08 = 00001000, 01 = 00000001, 28 = 00101000, 00 = 00000000
    final compressed = Uint8List.fromList([0x84, 0x40, 0x65, 0x10, 0x00]);
    final crc = crc16(compressed, 0, compressed.length);
    // Frame: header u16=0, frameLength u16, crc u16, timestamp u32, dados, pad (length ímpar)
    final frame = ByteData(10 + compressed.length + 1);
    frame.setUint16(0, 0, Endian.little);
    frame.setUint16(2, compressed.length, Endian.little);
    frame.setUint16(4, crc, Endian.little);
    frame.setUint32(6, 1000, Endian.little);
    final bytes = frame.buffer.asUint8List();
    bytes.setRange(10, 10 + compressed.length, compressed);

    final out = decodeStatsV2(
      blocks: [
        ScsEventBlock(
          startAddress: 0,
          rawTimestamp: 999999, // ignorado: frame traz o próprio timestamp
          status: kStatusActive,
          protocolVersion: 70,
          crc: 0,
          data: bytes,
        ),
      ],
      sensorToUnixOffsetSecs: 0,
      protocolVersion: 70,
    );
    expect(out.length, 1);
    expect(out.first.temperature, closeTo(11.8, 0.001));
    expect(out.first.timestamp.millisecondsSinceEpoch, 1000 * 1000);
  });

  test('bloco não comprimido: tag de temp1Ave vira leitura (temp = (v+78)/10)', () {
    final out = decodeStatsV2(
      blocks: [
        ScsEventBlock(
          startAddress: 0,
          rawTimestamp: 1000,
          status: 0xAAAA, // BUFFER1: não comprimido e usa o próprio rawTimestamp
          protocolVersion: 70,
          crc: 0,
          // tag 8 (temp1Ave), statLength 1, valor 0x0028 = 40 -> (40+78)/10 = 11.8
          data: Uint8List.fromList([8, 1, 40, 0, 0]),
        ),
      ],
      sensorToUnixOffsetSecs: 0,
      protocolVersion: 70,
    );
    expect(out.length, 1);
    expect(out.first.temperature, closeTo(11.8, 0.001));
    expect(out.first.timestamp.millisecondsSinceEpoch, 1000 * 1000);
  });
}
