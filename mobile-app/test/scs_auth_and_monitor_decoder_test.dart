import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aofrio_test_app/services/scs_auth.dart';
import 'package:aofrio_test_app/services/scs_stats_decoder.dart';

void main() {
  test('ScsAuth: pacote inicial de 11 bytes bate com ScsAuth.start', () {
    expect(
      buildScsAuthStartPacket(),
      [1, 0, 0, 0, 0, 0, 0, 2, 0, 7, 0],
    );
  });

  test('ScsAuth: handshake real com dados capturados do Monitor B152E02371', () async {
    final written = <Uint8List>[];
    int step = 0;

    // Respostas reais vistas no nRF Connect (specs/wellington_monitor_gatt.md):
    // Passo 1: [0x01, hashType=2 (RC4), challenge=0x4805D902]
    final step1Resp = Uint8List.fromList([0x01, 0x02, 0x02, 0xD9, 0x05, 0x48]);
    // Passo 2: 02070000004100070000000000011006000100 (19 bytes)
    // Obs.: no ByteArray little-endian de ScsAuth.onScsResponse:
    // byte 0 = 0x02, u16@1 = 0x0007, authStatus u16@3 = 0x0000,
    // protocolVersion u16@5 = 0x0041 (65), controllerCodeRevision u16@7 = 0x0007 (7),
    // otaCodeRevision u16@9 = 0x0000, highSideCodeRevision u16@11 = 0x0000,
    // productIdAndRevision u16@13 = 0x1001 (prodId=16 Monitor, rev=1)? No hex:
    // bytes 13..14 = 0x10, 0x01 -> prodId = 16!
    final step2Resp = Uint8List.fromList([
      0x02,
      0x07, 0x00, // u16@1
      0x00, 0x00, // authStatus = 0 (OK)
      0x41, 0x00, // protocolVersion = 65
      0x07, 0x00, // controllerCodeRevision = 7
      0x00, 0x00, // otaCodeRevision = 0
      0x00, 0x00, // highSideCodeRevision = 0
      0x01, 0x10, // 0x1001 = Monitor (byte alto = productId 16, baixo = rev 1)
      0x06, 0x00, // subRev = 6, beta = 0
      0x01,       // hardwareId = 1
      0x00,       // extraFlag = 0 (sem DH extra)
    ]);

    final res = await performScsAuthentication(
      writeAuth: (b) async {
        written.add(b);
      },
      readAuthResponse: () async {
        step++;
        return step == 1 ? step1Resp : step2Resp;
      },
      stepDelay: Duration.zero,
    );

    expect(written.length, 2);
    expect(written[0], [1, 0, 0, 0, 0, 0, 0, 2, 0, 7, 0]);
    expect(written[1].length, 9);
    expect(written[1][0], 2);
    expect(res.authStatus, 0);
    expect(res.protocolVersion, 65);
    expect(res.controllerCodeRevision, 7);
    expect(res.productId, 16);
    expect(res.supportsFastEventBlockRead, isTrue);
    expect(res.reportsBlockSize, isTrue);
  });

  test('decodeMonitorBlocks (pv < 64): avanço de tempo 12-bit + ITEM_TYPE_STATS_HEADER', () {
    // 1) ITEM_TYPE_ADVANCE_TIME_S (2): advance = 60s (0x03C)
    //    b0 = (0xC << 4) | 2 = 0xC2; b1 = 0x03 -> (0xC2 >> 4) + (0x03 << 4) = 12 + 48 = 60
    // 2) ITEM_TYPE_STATS_HEADER (4): bitmask = 8 (AVTEMP1 = bit 3)
    //    b0 = (0x8 << 4) | 4 = 0x84; b1 = 0x00 -> mask = 8 (1 bit ativo -> ímpar -> +1 byte pad)
    //    val = 0 -> temp = (0 + 78) / 10 = 7.8 °C
    // 3) Fim de bloco: 0xFF, 0xFF
    final data = Uint8List.fromList([
      0xC2, 0x03, // +60s
      0x84, 0x00, 0, 0x00, // mask=8, val=0 (7.8°C), pad=0
      0xFF, 0xFF,
    ]);

    final block = ScsEventBlock(
      startAddress: 0x1000,
      rawTimestamp: 1000,
      status: kStatusActive,
      protocolVersion: 7,
      crc: 0,
      data: data,
    );

    final readings = decodeScsFlashBlocks(
      blocks: [block],
      sensorToUnixOffsetSecs: 0,
      protocolVersion: 7,
      productId: 16,
    );

    expect(readings.length, 1);
    expect(readings.first.temperature, closeTo(7.8, 0.001));
    expect(readings.first.timestamp.millisecondsSinceEpoch, 1060 * 1000);
  });

  test('decodeMonitorBlocks (pv = 65): bit 8 (hi) + bit 16 (lo) em décimos de °C', () {
    // ITEM_TYPE_STATS_HEADER (4): mask = 8 | 16 = 24 = 0x018
    // b0 = (0x8 << 4) | 4 = 0x84; b1 = 0x01 -> mask = 24 (2 bits ativos -> par -> sem pad)
    // Temperatura = 3.5 °C -> raw16 = 35 = 0x0023 -> hi=0x00, lo=0x23
    final data = Uint8List.fromList([
      0x84, 0x01, 0x00, 0x23,
      0xFF, 0xFF,
    ]);

    final block = ScsEventBlock(
      startAddress: 0x1000,
      rawTimestamp: 2000,
      status: kStatusActive,
      protocolVersion: 65,
      crc: 0,
      data: data,
    );

    final readings = decodeScsFlashBlocks(
      blocks: [block],
      sensorToUnixOffsetSecs: 0,
      protocolVersion: 65,
      productId: 16,
    );

    expect(readings.length, 1);
    expect(readings.first.temperature, closeTo(3.5, 0.001));
    expect(readings.first.timestamp.millisecondsSinceEpoch, 2000 * 1000);
  });
}
