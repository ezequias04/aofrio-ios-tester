/// Define os parâmetros exigidos para o teste de uma categoria de refrigerador comercial
class TestProfile {
  final String id;
  final String name;
  final String standardName; // Referência da norma ou especificação
  final double targetTemperature; // Set-point alvo de pull-down (ex: 3.0°C ou -2.0°C)
  final double differential;      // Histerese de ciclagem permitida (ex: 1.0°C ou 2.0°C)
  final int? manualMaxAllowedMinutes; // Tempo máximo de ensaio permitido
  final double minInitialDrop15;  // Mínimo de queda exigido nos primeiros 15 min
  final double minStartingAmbientTemp; // Temperatura ambiente mínima para $T_0$ auditado
  final double? safetyMinTemperature; // Alerta de congelamento indevido

  const TestProfile({
    required this.id,
    required this.name,
    required this.standardName,
    required this.targetTemperature,
    this.differential = 1.5,
    this.manualMaxAllowedMinutes,
    this.minInitialDrop15 = 1.5,
    this.minStartingAmbientTemp = 24.0,
    this.safetyMinTemperature,
  });

  double get minTemperature => targetTemperature - differential;
  double get maxTemperature => targetTemperature + differential;

  /// Calcula o tempo máximo tolerado para o ensaio pull-down
  int calculateMaxAllowedMinutes(double ambientTemp) {
    if (manualMaxAllowedMinutes != null && manualMaxAllowedMinutes! > 0) {
      return manualMaxAllowedMinutes!;
    }
    final double deltaT = ambientTemp - targetTemperature;
    if (deltaT <= 0) return 30;
    final int minutes = (deltaT / 0.35 + 10).round();
    return minutes.clamp(30, 360);
  }

  static const List<TestProfile> defaultProfiles = [
    TestProfile(
      id: 'coca_cola_positive',
      name: 'Positiva Bebidas (Coca-Cola / KORE)',
      standardName: 'Padrão Coca-Cola Bottler Spec • KORE Engineering',
      targetTemperature: 3.0,
      differential: 1.0, // Faixa 2.0°C a 4.0°C
      manualMaxAllowedMinutes: 180, // Máx 3 horas
      minInitialDrop15: 1.5,
      minStartingAmbientTemp: 24.0,
      safetyMinTemperature: 0.0, // Proibido congelar refrigerante
    ),
    TestProfile(
      id: 'beer_cooler_subzero',
      name: 'Cervejeira Sub-Zero (Ambev / Heineken)',
      standardName: 'Padrão Comercial de Cervejeiras • Sub-Zero',
      targetTemperature: -2.0,
      differential: 2.0, // Faixa -4.0°C a 0.0°C
      manualMaxAllowedMinutes: 240, // Máx 4 horas
      minInitialDrop15: 1.5,
      minStartingAmbientTemp: 22.0,
      safetyMinTemperature: -5.0, // Alerta de congelamento de garrafa
    ),
    TestProfile(
      id: 'freezer_frozen_l1',
      name: 'Freezer Negativo / Sorvetes (ISO L1/L2)',
      standardName: 'ISO 23953 Classe L1/L2 • Alimentos Congelados',
      targetTemperature: -18.0,
      differential: 3.5, // Faixa -21.5°C a -14.5°C
      manualMaxAllowedMinutes: 360, // Máx 6 horas
      minInitialDrop15: 1.0,
      minStartingAmbientTemp: 20.0,
      safetyMinTemperature: -28.0,
    ),
    TestProfile(
      id: 'iso_23953_m1',
      name: 'ABNT NBR ISO 23953 (Classe M1)',
      standardName: 'Norma Brasileira ABNT NBR ISO 23953-2 Classe M1',
      targetTemperature: 3.5,
      differential: 1.5, // Faixa 2.0°C a 5.0°C
      manualMaxAllowedMinutes: 210, // 3,5 horas
      minInitialDrop15: 1.2,
      minStartingAmbientTemp: 24.0,
      safetyMinTemperature: -0.5,
    ),
  ];
}
