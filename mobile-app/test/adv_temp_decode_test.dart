import 'package:flutter_test/flutter_test.dart';
import 'package:aofrio_test_app/services/wellington_ble_service.dart';

void main() {
  test('decodeAdvTemp lê int16 LE /100 do offset 2-3', () {
    // Vetores capturados no hardware (asset GEUB031229).
    expect(WellingtonBleService.decodeAdvTemp([0x01, 0x00, 0xc4, 0x09]), 25.00); // 0x09c4
    expect(WellingtonBleService.decodeAdvTemp([0x01, 0x00, 0x1e, 0x0a]), 25.90); // 0x0a1e
  });

  test('decodeAdvTemp rejeita payload curto e fora de faixa', () {
    expect(WellingtonBleService.decodeAdvTemp([0x01, 0x00]), isNull);
    expect(WellingtonBleService.decodeAdvTemp([0x00, 0x00, 0xff, 0x7f]), isNull); // 327.67°C
  });
}
