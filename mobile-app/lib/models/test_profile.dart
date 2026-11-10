/// Define os parâmetros exigidos para o teste de uma categoria de geladeira
class TestProfile {
  final String id;
  final String name;
  final double targetTemperature; // Set-point (ex: 1.5°C ou 3.5°C)
  final double differential;      // Histerese de ciclagem (ex: 1.5°C)
  final int? manualMaxAllowedMinutes; // Se nulo, calcula automaticamente pela física
  final double minInitialDrop15;  // Mínimo de queda exigido nos primeiros 15 min

  const TestProfile({
    required this.id,
    required this.name,
    required this.targetTemperature,
    this.differential = 1.5,
    this.manualMaxAllowedMinutes,
    this.minInitialDrop15 = 1.5,
  });

  /// Calcula o tempo máximo tolerado com base nas normas ISO/ASHRAE para gabinete vazio:
  /// Taxa de resfriamento normativo de 0.35°C/min + 10 min de inércia da serpentina
  int calculateMaxAllowedMinutes(double ambientTemp) {
    if (manualMaxAllowedMinutes != null && manualMaxAllowedMinutes! > 0) {
      return manualMaxAllowedMinutes!;
    }
    final double deltaT = ambientTemp - targetTemperature;
    if (deltaT <= 0) return 30; // Já está na temperatura
    final int minutes = (deltaT / 0.35 + 10).round();
    return minutes.clamp(30, 240);
  }

  static const List<TestProfile> defaultProfiles = [
    TestProfile(
      id: 'bev_cooler_auto',
      name: 'Refrigerador de Bebidas (Set: 3.5°C, Dif: 1.5°C)',
      targetTemperature: 3.5,
      differential: 1.5,
      manualMaxAllowedMinutes: null, // Cálculo automático normativo
    ),
    TestProfile(
      id: 'cold_cooler_auto',
      name: 'Refrigerador Especial (Set: 1.5°C, Dif: 1.5°C)',
      targetTemperature: 1.5,
      differential: 1.5,
      manualMaxAllowedMinutes: null, // Cálculo automático normativo
    ),
    TestProfile(
      id: 'beer_cooler_auto',
      name: 'Cervejeira Trincando (Set: -2.0°C, Dif: 1.5°C)',
      targetTemperature: -2.0,
      differential: 1.5,
      manualMaxAllowedMinutes: null,
    ),
    TestProfile(
      id: 'freezer_auto',
      name: 'Freezer de Congelados (Set: -18.0°C, Dif: 2.0°C)',
      targetTemperature: -18.0,
      differential: 2.0,
      manualMaxAllowedMinutes: null,
    ),
  ];
}
