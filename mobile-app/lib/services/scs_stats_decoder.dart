import 'dart:typed_data';

import '../models/sensor_reading.dart';

/// Port do decodificador de log de estatísticas do Monitor, extraído do app
/// oficial SCS Field (bytecode do `Main.swf`): `ScsStatsBlocksDecoderV2`,
/// `Lzss`, `CRC16` e `StatisticSetVO.setValueV2`.
///
/// Layout do bloco de página (pageSize bytes, padrão 1024):
///   - cabeçalho de 16 bytes: timestamp u32 @0, status u16 @4,
///     protocolVersion u16 @6, CRC u16 @8 (dados não usados aqui).
///   - dados = bytes 16..pageSize, em frames LZSS com CRC16 próprio.
///
/// Só a temperatura média (tag 8, `temp1Ave`) vira leitura. As demais tags são
/// consumidas com o tamanho certo para manter o stream alinhado.

const int kBlockHeaderSize = 16;
const int kStatusActive = 0xFF00;
const int kStatusFull = 0x0000;
const int kStatusBuffer2 = 0xAAAB;

const int _tagEvent = 1;
const int _tagAdvanceTime = 2;
const int _tagOtaMajor = 3;
const int _tagOtaMinor = 4;
const int _tagSkipUnused = 240;
const int _tagTemp1Ave = 8; // fieldNameMapV2[8] -> EVENTCODE_STATS_AVTEMP1 (134)

/// Bloco bruto de página lido do sensor (cabeçalho já separado).
class ScsEventBlock {
  final int startAddress;
  final int rawTimestamp; // segundos no relógio do sensor
  final int status;
  final int protocolVersion;
  final int crc;
  final Uint8List data; // bytes após o cabeçalho de 16

  const ScsEventBlock({
    required this.startAddress,
    required this.rawTimestamp,
    required this.status,
    required this.protocolVersion,
    required this.crc,
    required this.data,
  });

  /// Monta o bloco a partir da página completa (cabeçalho + dados).
  factory ScsEventBlock.fromPage(int startAddress, Uint8List page) {
    final bd = ByteData.sublistView(page);
    return ScsEventBlock(
      startAddress: startAddress,
      rawTimestamp: bd.getUint32(0, Endian.little),
      status: bd.getUint16(4, Endian.little),
      protocolVersion: bd.getUint16(6, Endian.little),
      crc: bd.getUint16(8, Endian.little),
      data: Uint8List.sublistView(page, kBlockHeaderSize),
    );
  }
}

/// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, sem reflexão, xorout 0),
/// igual a `CRC16.calculate` do app oficial. Lê `length` bytes a partir de
/// `start`, limitado ao fim do buffer.
int crc16(Uint8List bytes, int start, int length) {
  var rem = 0xFFFF;
  final end = (start + length).clamp(0, bytes.length).toInt();
  for (var i = start; i < end; i++) {
    rem ^= bytes[i] << 8;
    for (var b = 0; b < 8; b++) {
      rem = (rem & 0x8000) != 0 ? ((rem << 1) ^ 0x1021) : (rem << 1);
      rem &= 0xFFFF;
    }
  }
  return rem & 0xFFFF;
}

/// LZSS (EI=9, EJ=4, N=512, F=17) igual à classe `Lzss` do app oficial.
/// O buffer de janela persiste entre frames do mesmo decode, como no original.
class _LzssDecoder {
  static const int _ei = 9;
  static const int _ej = 4;
  static const int _n = 1 << _ei;
  static const int _f = (1 << _ej) + 1;
  static const int _eof = -1000;

  final List<int> _window = List<int>.filled(_n, 0);
  List<int> _in = const [];
  int _pos = 0;
  int _cur = 0;
  int _mask = 0;

  List<int> decode(List<int> input) {
    _in = input;
    _pos = 0;
    _cur = 0;
    _mask = 0;
    for (var i = 0; i < _n - _f; i++) {
      _window[i] = 32;
    }
    final out = <int>[];
    var r = _n - _f;
    while (true) {
      final flag = _getBit(1);
      if (flag == _eof) break;
      if (flag != 0) {
        final lit = _getBit(8);
        if (lit == _eof) break;
        out.add(lit);
        _window[r] = lit;
        r = (r + 1) & (_n - 1);
      } else {
        final i = _getBit(_ei);
        if (i == _eof) break;
        final j = _getBit(_ej);
        if (j == _eof) break;
        for (var k = 0; k <= j + 1; k++) {
          final c = _window[(i + k) & (_n - 1)];
          out.add(c);
          _window[r] = c;
          r = (r + 1) & (_n - 1);
        }
      }
    }
    return out;
  }

  int _getBit(int n) {
    var x = 0;
    for (var i = 0; i < n; i++) {
      if (_mask == 0) {
        if (_pos >= _in.length) return _eof;
        _cur = _in[_pos++];
        _mask = 128;
      }
      x <<= 1;
      if ((_cur & _mask) != 0) x++;
      _mask >>= 1;
    }
    return x;
  }
}

/// Leitor little-endian com posição, equivalente ao ByteArray da AS3.
class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int pos = 0;

  int get available => bytes.length - pos;

  int u8() {
    if (pos >= bytes.length) throw const FormatException('fim do bloco');
    return bytes[pos++];
  }

  int u16() => u8() | (u8() << 8);

  int s16() {
    final v = u16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int u32() => u16() | (u16() << 16);
}

/// Equivalente a `ScsStatsBlocksDecoderV2.§_-Al§`: junta os frames LZSS de um
/// bloco ATIVO/CHEIO, seguindo para o bloco seguinte quando header == 1.
List<List<int>> _extractFrames(List<ScsEventBlock> blocks, int blockIndex) {
  final frames = <List<int>>[];
  var block = blocks[blockIndex];
  var r = _Reader(block.data);
  final lzss = _LzssDecoder();
  var complete = false;
  var peekingNext = false;

  while (!complete && r.available > 7) {
    final header = r.u16();
    if (header > 2) {
      complete = true;
      break;
    }
    final out = <int>[];
    final frameLength = r.u16();
    final crc = r.u16();
    final timestamp = r.u32();
    if (header < 2) {
      out.addAll([
        timestamp & 0xFF,
        (timestamp >> 8) & 0xFF,
        (timestamp >> 16) & 0xFF,
        (timestamp >> 24) & 0xFF,
      ]);
    }
    final crcOk = crc16(r.bytes, r.pos, frameLength) == crc;
    if (crcOk) {
      final compressed = <int>[];
      for (var i = 0; i < frameLength; i++) {
        compressed.add(r.u8());
      }
      if (frameLength % 2 != 0) r.u8();
      if (compressed.length >= 2 &&
          compressed[compressed.length - 2] == 255 &&
          compressed[compressed.length - 1] == 255) {
        r.u16();
      }
      out.addAll(lzss.decode(compressed));
      if (header == 2) {
        if (peekingNext) {
          frames.last.addAll(out);
          break;
        }
      } else {
        frames.add(out);
      }
      if (header == 1) {
        peekingNext = true;
        block = blocks[blockIndex + 1];
        r = _Reader(block.data);
      }
    }
  }
  return frames;
}

/// Converte o valor bruto de uma tag de temperatura, como `§_-Fs§` do original.
/// Retorna null quando o sensor marcou "sem dado" (255).
double? _convertTemp(int tag, int raw, int protocolVersion) {
  if (raw == 255) return null;
  var v = raw;
  if (v > 127) v -= 256;
  if (tag == _tagTemp1Ave) {
    return (v + 78) / 10.0;
  }
  return (protocolVersion < 64 ? v - 40 : v).toDouble();
}

/// Decodifica os blocos de estatística de um Monitor e devolve a curva de
/// temperatura média (temp1Ave), com horário em UTC.
///
/// [sensorToUnixOffsetSecs]: diferença entre o relógio do celular (Unix,
/// segundos) e o relógio do sensor, medida no momento da conexão.
/// [protocolVersion]: versão do protocolo do dispositivo.
List<SensorReading> decodeStatsV2({
  required List<ScsEventBlock> blocks,
  required int sensorToUnixOffsetSecs,
  required int protocolVersion,
  int pageSize = 1024,
}) {
  final readings = <SensorReading>[];

  void emitTemp(int sensorSecs, double? temp) {
    if (temp == null) return;
    final unixSecs = sensorSecs + sensorToUnixOffsetSecs;
    readings.add(SensorReading(
      timestamp: DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000, isUtc: true),
      temperature: double.parse(temp.toStringAsFixed(2)),
    ));
  }

  // Horário corrente persiste entre blocos, como a variável global do original.
  var currTs = 0;
  for (var bi = 0; bi < blocks.length; bi++) {
    final block = blocks[bi];
    if (block.status != kStatusBuffer2) {
      currTs = block.rawTimestamp;
    }

    if (block.status == kStatusFull &&
        crc16(block.data, 0, pageSize - kBlockHeaderSize) != block.crc) {
      continue; // CRC da página falhou: bloco descartado
    }

    final compressedStatus =
        block.status == kStatusActive || block.status == kStatusFull;
    final frames = compressedStatus ? _extractFrames(blocks, bi) : const <List<int>>[];
    if (compressedStatus && frames.isEmpty) continue;

    var frameIdx = 0;
    late _Reader r;
    if (compressedStatus) {
      r = _Reader(Uint8List.fromList(frames[0]));
      currTs = r.u32();
    } else {
      r = _Reader(block.data);
    }

    try {
      var tag = 0;
      var endOfBlock = false;
      while (!endOfBlock) {
        if (r.available > 0) tag = r.u8();
        if (r.available == 0 || tag == 0 || tag == 255) {
          if (!(compressedStatus && frameIdx < frames.length - 1)) {
            endOfBlock = true;
            continue;
          }
          frameIdx++;
          r = _Reader(Uint8List.fromList(frames[frameIdx]));
          currTs = r.u32();
          tag = r.u8();
        }
        final statLength = r.u8();

        switch (tag) {
          case _tagEvent:
            r.u16(); // código do evento: não usado na curva
            break;
          case _tagAdvanceTime:
            final adv = statLength == 1 ? r.u16() : r.u32();
            currTs += adv;
            break;
          case _tagOtaMajor:
          case _tagOtaMinor:
            r.u16();
            break;
          case _tagSkipUnused:
            r.pos += statLength * 2;
            break;
          default:
            if (statLength == 1) {
              final value = r.s16();
              if (tag == _tagTemp1Ave) {
                emitTemp(currTs, _convertTemp(tag, value, protocolVersion));
              }
            } else {
              r.pos += statLength * 2;
            }
        }
      }
    } on FormatException {
      // Fim inesperado do bloco: o resto dele é descartado, como no original.
    }
  }

  return readings;
}

/// Decodifica blocos do Wellington Monitor (`productId == 16`) ou dispositivos
/// com `protocolVersion < 30`, replicando a classe `_-CN` do bytecode de
/// `Main.swf` e `StatisticSetVO.setValue`.
///
/// No Monitor (ex.: `protocolVersion == 7`, `64`, `65`, `66+`), os blocos NÃO
/// usam compressão LZSS nem pares `[tag, statLength]`. Cada item começa com
/// `itemType = b0 & 0x0F`:
///   - `1` (`ITEM_TYPE_EVENT`): `[b0, code u8]` (2 B)
///   - `2` (`ITEM_TYPE_ADVANCE_TIME_S`): 12-bit int `(b0 >> 4) + (b1 << 4)` segundos (2 B)
///   - `3..6` (`EXT_STATS=3`, `STATS=4`, `DONGLE=5`, `DIAG=6`):
///     bitmask de 12 bits `(b0 >> 4) + (b1 << 4)` indicando quais dos 12 canais
///     têm 1 byte a seguir, mais 1 byte de alinhamento se o número de bits
///     ativos for ímpar.
///   - `7` (`ITEM_TYPE_FIRMWARE_UPDATE_HEADER`): 6 B no total (`b0`, `b1`,
///     `major u16 LE`, `minor u16 LE`).
///   - `0xFF, 0xFF`: fim do bloco.
List<SensorReading> decodeMonitorBlocks({
  required List<ScsEventBlock> blocks,
  required int sensorToUnixOffsetSecs,
  required int protocolVersion,
}) {
  final readings = <SensorReading>[];

  int countSetBits12(int mask) {
    int count = 0;
    for (int i = 0; i < 16; i++) {
      if ((mask & (1 << i)) != 0) count++;
    }
    return count;
  }

  for (final block in blocks) {
    final data = block.data;
    final pv = block.protocolVersion > 0 ? block.protocolVersion : protocolVersion;
    int currTs = block.rawTimestamp;
    int pos = 0;
    bool endOfBlock = false;

    int? curSampleTs;
    double? curTemp1Ave;
    double? curTemp1Min;
    double? curTemp1Max;
    int? curTempAmbRaw;
    int highByte = 0;
    double? monitorT1Ave;

    void flushSample() {
      if (curSampleTs == null || curTemp1Ave == null) return;
      double t = curTemp1Ave!;
      int ambOffset = 0;
      if (pv >= 22 && curTempAmbRaw != null) {
        ambOffset = curTempAmbRaw! > 127 ? curTempAmbRaw! - 256 : curTempAmbRaw!;
      }
      if ((t == -5.0 || t == 20.5) &&
          curTemp1Min != null &&
          curTemp1Max != null) {
        t = (curTemp1Min! + curTemp1Max!) / 2.0;
      } else {
        t = t + ambOffset;
      }
      if (t >= -50.0 && t <= 85.0) {
        final unixSecs = curSampleTs! + sensorToUnixOffsetSecs;
        readings.add(SensorReading(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            unixSecs * 1000,
            isUtc: true,
          ),
          temperature: double.parse(t.toStringAsFixed(2)),
        ));
      }
      curSampleTs = null;
      curTemp1Ave = null;
      curTemp1Min = null;
      curTemp1Max = null;
      curTempAmbRaw = null;
    }

    while (!endOfBlock && pos < data.length) {
      if (pos + 2 > data.length) break;
      final b0 = data[pos++];
      final b1 = data[pos++];
      if (b0 == 0xFF && b1 == 0xFF) {
        endOfBlock = true;
        break;
      }
      // Volta b1 para que cada caso leia como no original
      pos--;
      final itemType = b0 & 0x0F;

      switch (itemType) {
        case 1: // ITEM_TYPE_EVENT
          if (pos >= data.length) {
            endOfBlock = true;
            break;
          }
          pos++; // event code u8
          break;

        case 2: // ITEM_TYPE_ADVANCE_TIME_S
          if (pos >= data.length) {
            endOfBlock = true;
            break;
          }
          final nb = data[pos++];
          final advanceSecs = (b0 >> 4) + (nb << 4);
          currTs += advanceSecs;
          break;

        case 3: // ITEM_TYPE_EXT_STATS_HEADER
        case 4: // ITEM_TYPE_STATS_HEADER
        case 5: // ITEM_TYPE_DONGLE_HEADER
        case 6: // ITEM_TYPE_DIAG_HEADER
          if (pos >= data.length) {
            endOfBlock = true;
            break;
          }
          final nb = data[pos++];
          final mask = (b0 >> 4) + (nb << 4);
          final numBits = countSetBits12(mask);
          if (pos + numBits > data.length) {
            endOfBlock = true;
            break;
          }
          if (curSampleTs != null && curSampleTs != currTs) {
            flushSample();
          }
          curSampleTs = currTs;

          for (int bitIdx = 0; bitIdx < 12; bitIdx++) {
            final bitMask = 1 << bitIdx;
            if ((mask & bitMask) == 0) continue;
            final val = data[pos++];

            if (pv < 64) {
              if (itemType == 4) {
                // ITEM_TYPE_STATS_HEADER: bit 8=AVTEMP1, 16=MAXTEMP1, 32=MINTEMP1
                if (bitMask == 8 && val != 255) {
                  final signed = val > 127 ? val - 256 : val;
                  curTemp1Ave = (signed + 78) / 10.0;
                } else if (bitMask == 16 && val != 255) {
                  final signed = val > 127 ? val - 256 : val;
                  curTemp1Max = (signed - 40).toDouble();
                } else if (bitMask == 32 && val != 255) {
                  final signed = val > 127 ? val - 256 : val;
                  curTemp1Min = (signed - 40).toDouble();
                }
              } else if (itemType == 3 && bitMask == 1 && val != 255) {
                // ITEM_TYPE_EXT_STATS_HEADER: bit 1 = tempAmbAve
                curTempAmbRaw = val;
              } else if (itemType == 5 && bitMask == 4 && val != 255) {
                // ITEM_TYPE_DONGLE_HEADER: bit 4 = AVTEMP1
                final signed = val > 127 ? val - 256 : val;
                curTemp1Ave = (signed + 78) / 10.0;
              }
            } else if (pv == 64) {
              // maskType 100 (_-7W): bit 8=AVTEMP1, 32=MAXTEMP1, 64=MINTEMP1
              if (bitMask == 8 && val != 255) {
                final signed = val > 127 ? val - 256 : val;
                curTemp1Ave = (signed + 78) / 10.0;
              } else if (bitMask == 32 && val != 255) {
                final signed = val > 127 ? val - 256 : val;
                curTemp1Max = signed.toDouble();
              } else if (bitMask == 64 && val != 255) {
                final signed = val > 127 ? val - 256 : val;
                curTemp1Min = signed.toDouble();
              }
            } else if (pv == 65) {
              if (itemType == 4) {
                // MASK_TYPE_MONITOR_PV65_1 (102): bit 8=hi, 16=lo(AVTEMP1), 32=+max, 64=-min
                if (bitMask == 8) {
                  highByte = val;
                } else if (bitMask == 16) {
                  int raw16 = highByte * 256 + val;
                  if (raw16 > 32767) raw16 -= 65536;
                  if (raw16 != 32767) {
                    monitorT1Ave = raw16 / 10.0;
                    curTemp1Ave = monitorT1Ave;
                  } else {
                    monitorT1Ave = null;
                  }
                } else if (bitMask == 32 && monitorT1Ave != null && val < 255) {
                  curTemp1Max = monitorT1Ave + val / 10.0;
                } else if (bitMask == 64 && monitorT1Ave != null && val < 255) {
                  curTemp1Min = monitorT1Ave - val / 10.0;
                }
              }
            } else {
              // pv >= 66: maskType 101 (_-16): bit 1=hi, 2=lo(temp1Ave / 10)
              if (bitMask == 1 ||
                  bitMask == 4 ||
                  bitMask == 32 ||
                  bitMask == 1024) {
                highByte = val;
              } else if (bitMask == 2) {
                int raw16 = highByte * 256 + val;
                if (raw16 > 32767) raw16 -= 65536;
                if (raw16 != 32767) {
                  curTemp1Ave = raw16 / 10.0;
                }
              }
            }
          }
          // Byte extra de alinhamento quando o número de bits ativos é ímpar
          if ((numBits & 1) != 0 && pos < data.length) {
            pos++;
          }
          break;

        case 7: // ITEM_TYPE_FIRMWARE_UPDATE_HEADER
          // Consome o segundo byte do cabeçalho + 4 bytes de versão (major u16, minor u16)
          if (pos + 5 > data.length) {
            endOfBlock = true;
            break;
          }
          pos += 5;
          break;

        default:
          endOfBlock = true;
          break;
      }
    }
    flushSample();
  }

  return readings;
}

/// Ponto único de decodificação dos blocos da memória flash SCS:
/// usa o formato nativo do Monitor ([decodeMonitorBlocks]) e, caso o bloco
/// esteja no formato comprimido LZSS V2 (`productId == 1` com `pv == 30`),
/// faz fallback para [decodeStatsV2].
List<SensorReading> decodeScsFlashBlocks({
  required List<ScsEventBlock> blocks,
  required int sensorToUnixOffsetSecs,
  required int protocolVersion,
  int productId = 16,
  int pageSize = 1024,
}) {
  if (productId == 16 || protocolVersion < 30) {
    final monitorReadings = decodeMonitorBlocks(
      blocks: blocks,
      sensorToUnixOffsetSecs: sensorToUnixOffsetSecs,
      protocolVersion: protocolVersion,
    );
    if (monitorReadings.isNotEmpty) return monitorReadings;
  }
  final v2Readings = decodeStatsV2(
    blocks: blocks,
    sensorToUnixOffsetSecs: sensorToUnixOffsetSecs,
    protocolVersion: protocolVersion,
    pageSize: pageSize,
  );
  if (v2Readings.isNotEmpty) return v2Readings;
  return decodeMonitorBlocks(
    blocks: blocks,
    sensorToUnixOffsetSecs: sensorToUnixOffsetSecs,
    protocolVersion: protocolVersion,
  );
}

