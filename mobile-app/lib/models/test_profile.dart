/// Define os parâmetros normativos para qualificação e diagnóstico de um refrigerador comercial.
class TestProfile {
  final String id;
  final String name;
  final String shortLabel;
  final String categoryTag;
  final String standardName;
  final String description;
  final double targetTemperature;
  final double differential;
  final int? manualMaxAllowedMinutes;
  final double minInitialDrop15;
  final double minStartingAmbientTemp;
  final double? safetyMinTemperature;

  const TestProfile({
    required this.id,
    required this.name,
    this.shortLabel = '',
    this.categoryTag = 'Padrão',
    required this.standardName,
    this.description = '',
    required this.targetTemperature,
    this.differential = 1.5,
    this.manualMaxAllowedMinutes,
    this.minInitialDrop15 = 1.5,
    this.minStartingAmbientTemp = 24.0,
    this.safetyMinTemperature,
  });

  double get minTemperature => targetTemperature - differential;
  double get maxTemperature => targetTemperature + differential;

  String get displayShort =>
      shortLabel.isNotEmpty ? shortLabel : name.split(' (').first;

  /// Calcula o tempo máximo tolerado para o ensaio pull-down.
  int calculateMaxAllowedMinutes(double ambientTemp) {
    if (manualMaxAllowedMinutes != null && manualMaxAllowedMinutes! > 0) {
      return manualMaxAllowedMinutes!;
    }
    final double deltaT = ambientTemp - targetTemperature;
    if (deltaT <= 0) return 30;
    final int minutes = (deltaT / 0.35 + 10).round();
    return minutes.clamp(30, 360);
  }

  static TestProfile byId(String? id) {
    if (id == null || id.isEmpty) return defaultProfiles.first;
    return defaultProfiles.firstWhere(
      (p) => p.id == id,
      orElse: () => defaultProfiles.first,
    );
  }

  static const List<TestProfile> defaultProfiles = [
    TestProfile(
      id: 'coca_cola_positive',
      name: 'Positiva Bebidas (Coca-Cola / KORE)',
      shortLabel: 'Coca-Cola KORE',
      categoryTag: 'Positiva +3°C',
      standardName: 'Padrão Coca-Cola Bottler Spec • KORE Engineering',
      description:
          'Expositores verticais e visicoolers de refrigerantes/água. Faixa ideal de +2°C a +4°C em até 180 min; proibido atingir abaixo de 0°C.',
      targetTemperature: 3.0,
      differential: 1.0,
      manualMaxAllowedMinutes: 180,
      minInitialDrop15: 1.5,
      minStartingAmbientTemp: 24.0,
      safetyMinTemperature: 0.0,
    ),
    TestProfile(
      id: 'beer_cooler_subzero',
      name: 'Cervejeira Sub-Zero (Ambev / Heineken)',
      shortLabel: 'Cervejeira Sub-Zero',
      categoryTag: 'Sub-Zero -2°C',
      standardName: 'Padrão Comercial de Cervejeiras • Sub-Zero',
      description:
          'Cervejeiras comerciais de alta demanda. Meta -2°C (faixa -4°C a 0°C) em até 240 min; alerta crítico se cair abaixo de -5°C (risco de congelar garrafa).',
      targetTemperature: -2.0,
      differential: 2.0,
      manualMaxAllowedMinutes: 240,
      minInitialDrop15: 1.5,
      minStartingAmbientTemp: 22.0,
      safetyMinTemperature: -5.0,
    ),
    TestProfile(
      id: 'freezer_frozen_l1',
      name: 'Freezer Negativo / Sorvetes (ISO L1/L2)',
      shortLabel: 'Freezer ISO L1/L2',
      categoryTag: 'Congelados -18°C',
      standardName: 'ISO 23953 Classe L1/L2 • Alimentos Congelados',
      description:
          'Conservadores de gelo, sorvetes e congelados. Meta -18°C em até 360 min com controle de degeneração térmica.',
      targetTemperature: -18.0,
      differential: 3.5,
      manualMaxAllowedMinutes: 360,
      minInitialDrop15: 1.0,
      minStartingAmbientTemp: 20.0,
      safetyMinTemperature: -28.0,
    ),
    TestProfile(
      id: 'iso_23953_m1',
      name: 'ABNT NBR ISO 23953 (Classe M1)',
      shortLabel: 'ABNT ISO M1',
      categoryTag: 'Positiva +3,5°C',
      standardName: 'Norma Brasileira ABNT NBR ISO 23953-2 Classe M1',
      description:
          'Balcões e expositores comerciais gerais pela norma brasileira. Meta +3,5°C (faixa +2°C a +5°C) em até 210 min.',
      targetTemperature: 3.5,
      differential: 1.5,
      manualMaxAllowedMinutes: 210,
      minInitialDrop15: 1.2,
      minStartingAmbientTemp: 24.0,
      safetyMinTemperature: -0.5,
    ),
  ];
}
