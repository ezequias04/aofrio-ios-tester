import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';

/// Motor de Cálculo do Ensaio Pull-Down Adaptativo
/// Analisa séries temporais extraídas da memória flash do sensor AoFrio / Wellington
class PullDownAnalyzer {
  
  /// Executa o algoritmo de qualificação térmica adaptativa
  static TestResult analyze({
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    required List<SensorReading> readings,
  }) {
    if (readings.length < 5) {
      throw ArgumentError('Série temporal com dados insuficientes para análise.');
    }

    // 1. Identificar o ponto de partida (t0) onde a temperatura começa a cair
    int startIndex = _findPullDownStartIndex(readings);
    final startReading = readings[startIndex];
    final double initialTemp = startReading.temperature;

    // Tempo máximo adaptativo para gabinete vazio
    final int allowedMinutes = profile.calculateMaxAllowedMinutes(initialTemp);

    // 2. Verificar se após 15 minutos houve queda mínima de resposta (compressor partiu)
    final fifteenMinIndex = _findReadingAtOffset(readings, startIndex, const Duration(minutes: 15));
    if (fifteenMinIndex != null) {
      final double dropAt15 = initialTemp - readings[fifteenMinIndex].temperature;
      if (dropAt15 < profile.minInitialDrop15) {
        return _buildResult(
          serialNumber: serialNumber,
          modelName: modelName,
          technicianName: technicianName,
          profile: profile,
          status: TestStatus.reprovada,
          reason: 'Falha de partida ou resposta lenta: a temperatura caiu apenas '
              '${dropAt15.toStringAsFixed(1)}°C nos primeiros 15 min (mínimo exigido: ${profile.minInitialDrop15}°C). '
              'Verifique relé de partida, termostato ou carga de fluido.',
          startReading: startReading,
          endReading: readings.last,
          readings: readings.sublist(startIndex),
          effectiveAllowedMinutes: allowedMinutes,
        );
      }
    }

    // 3. Checar se houve choque térmico prolongado por porta aberta (Recálculo Dinâmico de Rota)
    int? doorOpenStart;
    int? doorOpenEnd;
    for (int i = startIndex; i < readings.length; i++) {
      if (readings[i].doorOpen) {
        doorOpenStart ??= i;
        doorOpenEnd = i;
      }
    }

    bool hadThermalShock = false;
    int shockToleranceExtra = 0;
    if (doorOpenStart != null && doorOpenEnd != null) {
      final openMinutes = readings[doorOpenEnd].timestamp.difference(readings[doorOpenStart].timestamp).inMinutes;
      if (openMinutes >= 3) {
        hadThermalShock = true;
        // Compensação: tempo da porta aberta + 50% de prazo para rebaixar o ar quente
        shockToleranceExtra = openMinutes + (openMinutes * 0.5).round();
      }
    }

    final int totalAdjustedAllowedMinutes = allowedMinutes + shockToleranceExtra;

    // 4. Procurar o momento em que atinge a temperatura alvo
    int? targetReachedIndex;
    for (int i = startIndex; i < readings.length; i++) {
      if (readings[i].temperature <= profile.targetTemperature) {
        targetReachedIndex = i;
        break;
      }
    }

    // Caso NÃO tenha atingido a meta
    if (targetReachedIndex == null) {
      final lastReading = readings.last;
      final duration = lastReading.timestamp.difference(startReading.timestamp).inMinutes;
      return _buildResult(
        serialNumber: serialNumber,
        modelName: modelName,
        technicianName: technicianName,
        profile: profile,
        status: TestStatus.reprovada,
        reason: 'Meta não alcançada: Após $duration minutos de funcionamento, '
            'a temperatura estabilizou em ${lastReading.temperature.toStringAsFixed(1)}°C, '
            'sem atingir o setpoint de ${profile.targetTemperature}°C '
            '(tempo limite normativo era $totalAdjustedAllowedMinutes min).',
        startReading: startReading,
        endReading: lastReading,
        readings: readings.sublist(startIndex),
        effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
      );
    }

    // Caso TENHA atingido a meta
    final targetReading = readings[targetReachedIndex];
    final durationMinutes = targetReading.timestamp.difference(startReading.timestamp).inMinutes;
    final testSlice = readings.sublist(startIndex, targetReachedIndex + 1);

    // 5. Checar tempo de pull-down com a tolerância adaptada
    if (durationMinutes > totalAdjustedAllowedMinutes) {
      return _buildResult(
        serialNumber: serialNumber,
        modelName: modelName,
        technicianName: technicianName,
        profile: profile,
        status: TestStatus.reprovada,
        reason: 'Tempo limite excedido: O refrigerador levou $durationMinutes minutos para atingir '
            '${profile.targetTemperature}°C (limite calculado pelas normas: $totalAdjustedAllowedMinutes min).',
        startReading: startReading,
        endReading: targetReading,
        readings: testSlice,
        effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
      );
    }

    // 6. Monta o veredito de aprovação (Normal ou com Recuperação de Choque Térmico)
    final doorOpenCount = testSlice.where((r) => r.doorOpen).length;
    String verdictReason;

    if (hadThermalShock) {
      verdictReason = 'APROVADA COM RECUPERAÇÃO TÉRMICA! Atingiu ${targetReading.temperature.toStringAsFixed(1)}°C '
          'em $durationMinutes minutos mesmo após choque térmico de porta aberta. '
          'O sistema frigorífico comprovou alta resiliência e capacidade de extração de calor.';
    } else {
      verdictReason = 'APROVADA com sucesso! Atingiu ${targetReading.temperature.toStringAsFixed(1)}°C '
          'em $durationMinutes minutos (meta calculada pelas normas era até $totalAdjustedAllowedMinutes min).';
      if (doorOpenCount > 0) {
        verdictReason += ' (Detectada $doorOpenCount oscilação rápida de porta durante o ensaio).';
      }
    }

    return _buildResult(
      serialNumber: serialNumber,
      modelName: modelName,
      technicianName: technicianName,
      profile: profile,
      status: TestStatus.aprovada,
      reason: verdictReason,
      startReading: startReading,
      endReading: targetReading,
      readings: testSlice,
      effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
    );
  }

  static int _findPullDownStartIndex(List<SensorReading> readings) {
    for (int i = 0; i < readings.length - 3; i++) {
      if (readings[i + 1].temperature < readings[i].temperature &&
          readings[i + 2].temperature < readings[i + 1].temperature) {
        return i;
      }
    }
    return 0;
  }

  static int? _findReadingAtOffset(List<SensorReading> readings, int startIdx, Duration offset) {
    final targetTime = readings[startIdx].timestamp.add(offset);
    for (int i = startIdx; i < readings.length; i++) {
      if (readings[i].timestamp.isAfter(targetTime) || readings[i].timestamp.isAtSameMomentAs(targetTime)) {
        return i;
      }
    }
    return null;
  }

  static TestResult _buildResult({
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    required TestStatus status,
    required String reason,
    required SensorReading startReading,
    required SensorReading endReading,
    required List<SensorReading> readings,
    required int effectiveAllowedMinutes,
  }) {
    final durationMin = endReading.timestamp.difference(startReading.timestamp).inMinutes.clamp(1, 9999);
    final tempDrop = startReading.temperature - endReading.temperature;
    final coolingRate = tempDrop / durationMin;
    final doorEvents = readings.where((r) => r.doorOpen).length;
    final compressorActiveCount = readings.where((r) => r.compressorOn).length;
    final dutyCycle = readings.isNotEmpty ? compressorActiveCount / readings.length : 1.0;

    return TestResult(
      testId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      serialNumber: serialNumber,
      modelName: modelName,
      technicianName: technicianName,
      profile: profile,
      status: status,
      verdictReason: reason,
      startTime: startReading.timestamp,
      endTime: endReading.timestamp,
      durationMinutes: durationMin,
      initialTemp: startReading.temperature,
      finalTemp: endReading.temperature,
      coolingRate: coolingRate,
      doorOpenEvents: doorEvents,
      compressorDutyCycle: dutyCycle,
      readings: readings,
    );
  }
}
