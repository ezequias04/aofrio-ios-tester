import 'package:aofrio_test_app/services/wellington_ble_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pacote do fabricante 0x578: header 01 00 + temperatura int16 LE em
/// centésimos de °C + nome do ativo em ASCII (formato confirmado no hardware).
List<int> mfr(double temp, String asset) {
  final raw = (temp * 100).round() & 0xFFFF;
  return [0x01, 0x00, raw & 0xFF, raw >> 8, ...asset.codeUnits];
}

void main() {
  final t0 = DateTime(2026, 11, 24, 21, 29);
  const id = '365DBD29-8EE3-3BDC-8902-66B7F34';
  const serial = 'B152E02371079226226';

  LiveTelemetry merge(LiveTelemetry? prev, List<int>? m, DateTime now, DateTime? lastMfr) =>
      WellingtonBleService.mergeAdvertisement(
        deviceId: id,
        prev: prev,
        mfr: m,
        scanName: serial,
        rssi: -60,
        now: now,
        lastMfrAt: lastMfr,
      );

  test('pacote do fabricante traz o GEUB e a temperatura', () {
    final t = merge(null, mfr(26.7, 'GEUB031229'), t0, null);
    expect(t.assetName, 'GEUB031229');
    expect(t.temperatureC, closeTo(26.7, 0.001));
  });

  test('resposta de scan (só o serial) não apaga GEUB nem temperatura', () {
    final a = merge(null, mfr(26.7, 'GEUB031229'), t0, null);
    final b = merge(a, null, t0.add(const Duration(seconds: 2)), t0);
    expect(b.assetName, 'GEUB031229');
    expect(b.temperatureC, closeTo(26.7, 0.001));
  });

  test('sem pacote do fabricante por 30 s a temperatura some, o nome fica', () {
    final a = merge(null, mfr(26.7, 'GEUB031229'), t0, null);
    final b = merge(a, null, t0.add(const Duration(seconds: 31)), t0);
    expect(b.assetName, 'GEUB031229');
    expect(b.temperatureC, isNull);
  });

  test('scan antes do fabricante mostra o serial e depois trava no GEUB', () {
    final a = merge(null, null, t0, null);
    expect(a.assetName, serial);
    expect(a.temperatureC, isNull);
    final b = merge(a, mfr(25.0, 'GEUB031229'), t0.add(const Duration(seconds: 1)), null);
    expect(b.assetName, 'GEUB031229');
    expect(b.temperatureC, closeTo(25.0, 0.001));
  });
}
