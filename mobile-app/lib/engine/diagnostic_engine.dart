import 'dart:math' as math;

import '../models/diagnostic_finding.dart';
import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';

/// Motor de Diagnóstico Frigorífico & Análise Pull-Down (ISO 23953 / Coca-Cola KORE).
/// Analisa séries temporais em tempo real na bancada e gera laudos com causa raiz
/// e checklist técnico de reparo.
class DiagnosticEngine {
  /// Avalia o comportamento térmico em tempo real para exibir fase, taxa, ETA
  /// e eventuais indícios de falha enquanto o ensaio ainda está rodando.
  static LiveDiagnosticSnapshot evaluateLive({
    required TestProfile profile,
    required List<SensorReading> readings,
    required DateTime startedAt,
    DateTime? now,
    String reportedSymptom = '',
  }) {
    if (readings.isEmpty) {
      return const LiveDiagnosticSnapshot(
        phase: DiagnosticPhase.aguardandoSinal,
        health: LiveHealth.atencao,
        headline: 'Aguardando primeira telemetria do sensor',
        subtext:
            'Mantenha o celular próximo ao sensor Wellington/AoFrio para capturar T0.',
      );
    }

    final sorted = List<SensorReading>.from(readings)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final currentTime = now ?? DateTime.now();
    final initialTemp = sorted.first.temperature;
    final currentTemp = sorted.last.temperature;

    var minTemp = sorted.first.temperature;
    var maxTemp = sorted.first.temperature;
    DateTime? targetTime;

    for (final r in sorted) {
      if (r.temperature < minTemp) minTemp = r.temperature;
      if (r.temperature > maxTemp) maxTemp = r.temperature;
      if (targetTime == null && r.temperature <= profile.targetTemperature) {
        targetTime = r.timestamp;
      }
    }

    final deltaTemp = initialTemp - currentTemp;
    final spanSecs =
        math.max(0, sorted.last.timestamp.difference(sorted.first.timestamp).inSeconds);
    final elapsedSecs =
        math.max(spanSecs, currentTime.difference(startedAt).inSeconds);
    final elapsedMin = elapsedSecs / 60.0;

    final averageCoolingRate =
        spanSecs >= 30 ? deltaTemp / (spanSecs / 60.0) : 0.0;

    // Taxa recente nos últimos 10 minutos (ou janela disponível >= 30 s)
    final windowAnchor = sorted.last.timestamp.subtract(const Duration(minutes: 10));
    SensorReading recentStart = sorted.first;
    for (final r in sorted) {
      if (!r.timestamp.isBefore(windowAnchor)) {
        recentStart = r;
        break;
      }
    }
    final recentSecs =
        sorted.last.timestamp.difference(recentStart.timestamp).inSeconds;
    final recentCoolingRate = recentSecs >= 30
        ? (recentStart.temperature - currentTemp) / (recentSecs / 60.0)
        : averageCoolingRate;

    final t0Validated = initialTemp >= profile.minStartingAmbientTemp;
    final antiFreezeViolation = profile.safetyMinTemperature != null &&
        minTemp < profile.safetyMinTemperature!;
    final targetReached = targetTime != null;
    final targetReachedMinutes = targetTime?.difference(startedAt).inMinutes;

    // Queda aos 15 minutos
    double? dropAt15;
    final idx15 = _findReadingAtOffset(
      sorted,
      0,
      const Duration(minutes: 15),
    );
    if (idx15 != null) {
      dropAt15 = initialTemp - sorted[idx15].temperature;
    }

    // Progresso até o setpoint
    double progressRatio = 0.0;
    if (targetReached) {
      progressRatio = 1.0;
    } else if (initialTemp > profile.targetTemperature) {
      progressRatio = ((initialTemp - currentTemp) /
              (initialTemp - profile.targetTemperature))
          .clamp(0.0, 1.0);
    }

    // Estimativa de tempo restante (ETA) baseada na taxa recente ou média
    int? estimatedMinutes;
    if (!targetReached) {
      final rateForEta =
          recentCoolingRate > 0.04 ? recentCoolingRate : averageCoolingRate;
      if (rateForEta > 0.04) {
        final remainingDeg =
            math.max(0.0, currentTemp - profile.targetTemperature);
        estimatedMinutes = (remainingDeg / rateForEta).round().clamp(1, 999);
      }
    }

    // Construção de diagnóstico preliminar ao vivo
    DiagnosticFinding? preliminary;
    DiagnosticPhase phase;
    LiveHealth health;
    String headline;
    String subtext;

    if (antiFreezeViolation) {
      phase = DiagnosticPhase.alertaCongelamento;
      health = LiveHealth.critico;
      headline =
          'Alerta: ${minTemp.toStringAsFixed(1)}°C abaixo do limite (${profile.safetyMinTemperature}°C)';
      subtext =
          'Controlador não cortou o compressor na faixa segura. Risco de congelar bebidas.';
      preliminary = _buildFreezeFinding(
        minTemp: minTemp,
        profile: profile,
        isCritical: true,
      );
    } else if (targetReached) {
      phase = DiagnosticPhase.metaAtingida;
      health = LiveHealth.excelente;
      headline =
          'Setpoint ${profile.targetTemperature.toStringAsFixed(1)}°C atingido aos ${targetReachedMinutes ?? elapsedMin.round()} min';
      subtext =
          'Sistema atingiu a meta normativa. Você já pode encerrar e emitir o laudo oficial.';
    } else if (dropAt15 != null && dropAt15 < profile.minInitialDrop15) {
      phase = DiagnosticPhase.verificandoPartida;
      health = LiveHealth.critico;
      headline =
          'Partida lenta: caiu apenas ${dropAt15.toStringAsFixed(1)}°C em 15 min';
      subtext =
          'Mínimo exigido era ${profile.minInitialDrop15.toStringAsFixed(1)}°C. Suspeita de falha no compressor ou carga crítica.';
      preliminary = _buildCompressorStartFinding(
        dropAt15: dropAt15,
        profile: profile,
        reportedSymptom: reportedSymptom,
      );
    } else if (elapsedMin >= 20 &&
        deltaTemp >= 3.0 &&
        minTemp > profile.targetTemperature + 3.0 &&
        (currentTemp - minTemp) >= 1.5) {
      phase = DiagnosticPhase.emResfriamento;
      health = LiveHealth.critico;
      headline =
          'Reaquecimento detectado (+${(currentTemp - minTemp).toStringAsFixed(1)}°C)';
      subtext =
          'Temperatura subiu após mínima de ${minTemp.toStringAsFixed(1)}°C. Verifique gelo no evaporador, ventilador ou vedação.';
      preliminary = _buildStallFinding(
        minTemp: minTemp,
        finalTemp: currentTemp,
        profile: profile,
      );
    } else if (elapsedMin >= 25 && recentCoolingRate < 0.04) {
      phase = DiagnosticPhase.emResfriamento;
      health = LiveHealth.atencao;
      headline =
          'Queda estagnada (${recentCoolingRate.toStringAsFixed(2)}°C/min)';
      subtext =
          'Taxa de resfriamento muito baixa em ${currentTemp.toStringAsFixed(1)}°C. Verifique condensador e carga de fluido.';
      preliminary = _buildLowEfficiencyFinding(
        durationMinutes: elapsedMin.round(),
        finalTemp: currentTemp,
        allowedMinutes: profile.calculateMaxAllowedMinutes(initialTemp),
        profile: profile,
      );
    } else if (elapsedMin < 3) {
      phase = DiagnosticPhase.auditoriaInicial;
      health = t0Validated ? LiveHealth.normal : LiveHealth.atencao;
      headline = t0Validated
          ? 'Baseline T0 validado (${initialTemp.toStringAsFixed(1)}°C)'
          : 'Gabinete pré-resfriado (${initialTemp.toStringAsFixed(1)}°C)';
      subtext = t0Validated
          ? 'Monitorando resposta inicial de partida do compressor.'
          : 'Abaixo de ${profile.minStartingAmbientTemp}°C recomendados; ensaio prosseguirá com registro de auditoria.';
    } else if (elapsedMin < 15) {
      phase = DiagnosticPhase.verificandoPartida;
      health = deltaTemp >= 0.8 ? LiveHealth.excelente : LiveHealth.normal;
      headline =
          'Verificando partida • Δ ${deltaTemp >= 0 ? '-' : '+'}${deltaTemp.abs().toStringAsFixed(1)}°C';
      subtext =
          'Checagem obrigatória dos primeiros 15 min (meta mínima ≥ ${profile.minInitialDrop15}°C).';
    } else {
      phase = DiagnosticPhase.emResfriamento;
      health = recentCoolingRate >= 0.15
          ? LiveHealth.excelente
          : LiveHealth.normal;
      headline =
          'Resfriando a ${recentCoolingRate.toStringAsFixed(2)}°C/min';
      subtext = estimatedMinutes != null
          ? 'Previsão de atingir ${profile.targetTemperature}°C em ~$estimatedMinutes min.'
          : 'Coletando pontos para projetar estabilidade térmica.';
    }

    return LiveDiagnosticSnapshot(
      phase: phase,
      health: health,
      headline: headline,
      subtext: subtext,
      initialTemp: initialTemp,
      currentTemp: currentTemp,
      minTemp: minTemp,
      maxTemp: maxTemp,
      deltaTemp: deltaTemp,
      dropAt15Min: dropAt15,
      recentCoolingRate: recentCoolingRate,
      averageCoolingRate: averageCoolingRate,
      estimatedMinutesToTarget: estimatedMinutes,
      targetReached: targetReached,
      targetReachedMinutes: targetReachedMinutes,
      t0Validated: t0Validated,
      antiFreezeViolation: antiFreezeViolation,
      progressRatio: progressRatio,
      preliminaryFinding: preliminary,
    );
  }

  /// Gera o laudo técnico final e a classificação de falha a partir da curva gravada.
  static TestResult diagnose({
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    required List<SensorReading> readings,
    String sensorId = '',
    String sensorName = '',
    String reportedSymptom = '',
    String dataSource = 'BLE Ao Vivo',
    bool isSimulated = false,
    List<String> manualNotes = const [],
    bool allowPartial = false,
  }) {
    final minRequired = allowPartial ? 2 : 5;
    if (readings.length < minRequired) {
      throw ArgumentError(
        'Série temporal com dados insuficientes para análise (mínimo $minRequired leituras).',
      );
    }

    final sorted = List<SensorReading>.from(readings)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 1. Ponto de partida (T0) onde inicia a queda térmica
    final startIndex = _findPullDownStartIndex(sorted);
    final startReading = sorted[startIndex];
    final double initialTemp = startReading.temperature;
    final bool t0Validated = initialTemp >= profile.minStartingAmbientTemp;

    final int allowedMinutes = profile.calculateMaxAllowedMinutes(initialTemp);

    // 2. Checagem de partida nos primeiros 15 minutos
    final fifteenMinIndex =
        _findReadingAtOffset(sorted, startIndex, const Duration(minutes: 15));
    if (fifteenMinIndex != null) {
      final double dropAt15 = initialTemp - sorted[fifteenMinIndex].temperature;
      if (dropAt15 < profile.minInitialDrop15) {
        final finding = _buildCompressorStartFinding(
          dropAt15: dropAt15,
          profile: profile,
          reportedSymptom: reportedSymptom,
        );
        return _buildResult(
          serialNumber: serialNumber,
          modelName: modelName,
          technicianName: technicianName,
          profile: profile,
          status: TestStatus.reprovada,
          reason: finding.summary,
          startReading: startReading,
          endReading: sorted.last,
          readings: sorted.sublist(startIndex),
          effectiveAllowedMinutes: allowedMinutes,
          finding: finding,
          sensorId: sensorId,
          sensorName: sensorName,
          reportedSymptom: reportedSymptom,
          dataSource: dataSource,
          t0Validated: t0Validated,
          isSimulated: isSimulated,
          manualNotes: manualNotes,
        );
      }
    }

    // 3. Tolerância para choque térmico de porta aberta (quando sinalizado)
    int? doorOpenStart;
    int? doorOpenEnd;
    for (int i = startIndex; i < sorted.length; i++) {
      if (sorted[i].doorOpen) {
        doorOpenStart ??= i;
        doorOpenEnd = i;
      }
    }

    bool hadThermalShock = false;
    int shockToleranceExtra = 0;
    if (doorOpenStart != null && doorOpenEnd != null) {
      final openMinutes = sorted[doorOpenEnd]
          .timestamp
          .difference(sorted[doorOpenStart].timestamp)
          .inMinutes;
      if (openMinutes >= 3) {
        hadThermalShock = true;
        shockToleranceExtra = openMinutes + (openMinutes * 0.5).round();
      }
    }

    final int totalAdjustedAllowedMinutes = allowedMinutes + shockToleranceExtra;

    // 4. Checar segurança contra congelamento severo em todo o ensaio
    final postStartSlice = sorted.sublist(startIndex);
    double lowestTemp = postStartSlice.first.temperature;
    int freezeSamples = 0;
    for (final r in postStartSlice) {
      if (r.temperature < lowestTemp) lowestTemp = r.temperature;
      if (profile.safetyMinTemperature != null &&
          r.temperature < profile.safetyMinTemperature!) {
        freezeSamples++;
      }
    }

    final bool criticalFreezeFailure = profile.safetyMinTemperature != null &&
        (lowestTemp < profile.safetyMinTemperature! - 0.5 ||
            freezeSamples >= 3);

    if (criticalFreezeFailure) {
      final finding = _buildFreezeFinding(
        minTemp: lowestTemp,
        profile: profile,
        isCritical: true,
      );
      return _buildResult(
        serialNumber: serialNumber,
        modelName: modelName,
        technicianName: technicianName,
        profile: profile,
        status: TestStatus.reprovada,
        reason: finding.summary,
        startReading: startReading,
        endReading: sorted.last,
        readings: postStartSlice,
        effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
        finding: finding,
        sensorId: sensorId,
        sensorName: sensorName,
        reportedSymptom: reportedSymptom,
        dataSource: dataSource,
        t0Validated: t0Validated,
        isSimulated: isSimulated,
        manualNotes: manualNotes,
      );
    }

    // 5. Verificar atingimento da meta térmica
    int? targetReachedIndex;
    for (int i = startIndex; i < sorted.length; i++) {
      if (sorted[i].temperature <= profile.targetTemperature) {
        targetReachedIndex = i;
        break;
      }
    }

    // Caso NÃO tenha atingido o setpoint
    if (targetReachedIndex == null) {
      final lastReading = sorted.last;
      final durationMinutes = math.max(
        1,
        lastReading.timestamp.difference(startReading.timestamp).inMinutes,
      );
      final totalDrop = initialTemp - lastReading.temperature;
      final avgRate = totalDrop / durationMinutes;

      // Assinatura 1: Reaquecimento ou estagnação prolongada em platô quente
      final bool hasRebound = (initialTemp - lowestTemp) >= 4.0 &&
          lowestTemp > profile.targetTemperature + 3.0 &&
          (lastReading.temperature - lowestTemp) >= 1.5;

      final bool hasProlongedPlateau = _hasProlongedPlateau(
        postStartSlice,
        targetTemp: profile.targetTemperature,
      );

      if (hasRebound || hasProlongedPlateau) {
        final finding = _buildStallFinding(
          minTemp: lowestTemp,
          finalTemp: lastReading.temperature,
          profile: profile,
        );
        return _buildResult(
          serialNumber: serialNumber,
          modelName: modelName,
          technicianName: technicianName,
          profile: profile,
          status: TestStatus.reprovada,
          reason: finding.summary,
          startReading: startReading,
          endReading: lastReading,
          readings: postStartSlice,
          effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
          finding: finding,
          sensorId: sensorId,
          sensorName: sensorName,
          reportedSymptom: reportedSymptom,
          dataSource: dataSource,
          t0Validated: t0Validated,
          isSimulated: isSimulated,
          manualNotes: manualNotes,
        );
      }

      // Assinatura 2: Ensaio encerrado cedo com curva saudável em andamento
      if (allowPartial &&
          durationMinutes < totalAdjustedAllowedMinutes &&
          avgRate >= 0.12) {
        final eta = ((lastReading.temperature - profile.targetTemperature) /
                avgRate)
            .round()
            .clamp(1, 600);
        final finding = DiagnosticFinding(
          category: FaultCategory.ensaioInterrompido,
          title: FaultCategory.ensaioInterrompido.label,
          summary:
              'Ensaio encerrado antes da conclusão aos $durationMinutes min em ${lastReading.temperature.toStringAsFixed(1)}°C '
              '(taxa saudável de ${avgRate.toStringAsFixed(2)}°C/min; previsão de atingir ${profile.targetTemperature}°C em ~$eta min adicionais).',
          probableCauses: const [
            'Coleta encerrada manualmente antes do prazo normativo completo.',
          ],
          recommendedActions: const [
            'Repetir ou continuar o ensaio até completar a janela pull-down ou baixar o log da memória flash do sensor após estabilização.',
          ],
          isCritical: false,
        );
        return _buildResult(
          serialNumber: serialNumber,
          modelName: modelName,
          technicianName: technicianName,
          profile: profile,
          status: TestStatus.inconclusiva,
          reason: finding.summary,
          startReading: startReading,
          endReading: lastReading,
          readings: postStartSlice,
          effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
          finding: finding,
          sensorId: sensorId,
          sensorName: sensorName,
          reportedSymptom: reportedSymptom,
          dataSource: dataSource,
          t0Validated: t0Validated,
          isSimulated: isSimulated,
          manualNotes: manualNotes,
        );
      }

      // Assinatura 3: Falha quase total de partida / compressor parado
      if (totalDrop < 2.0 && durationMinutes >= 15) {
        final finding = _buildCompressorStartFinding(
          dropAt15: totalDrop,
          profile: profile,
          reportedSymptom: reportedSymptom,
        );
        return _buildResult(
          serialNumber: serialNumber,
          modelName: modelName,
          technicianName: technicianName,
          profile: profile,
          status: TestStatus.reprovada,
          reason: finding.summary,
          startReading: startReading,
          endReading: lastReading,
          readings: postStartSlice,
          effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
          finding: finding,
          sensorId: sensorId,
          sensorName: sensorName,
          reportedSymptom: reportedSymptom,
          dataSource: dataSource,
          t0Validated: t0Validated,
          isSimulated: isSimulated,
          manualNotes: manualNotes,
        );
      }

      // Assinatura 4: Baixa eficiência térmica / carga de gás insuficiente
      final finding = _buildLowEfficiencyFinding(
        durationMinutes: durationMinutes,
        finalTemp: lastReading.temperature,
        allowedMinutes: totalAdjustedAllowedMinutes,
        profile: profile,
      );
      return _buildResult(
        serialNumber: serialNumber,
        modelName: modelName,
        technicianName: technicianName,
        profile: profile,
        status: TestStatus.reprovada,
        reason: finding.summary,
        startReading: startReading,
        endReading: lastReading,
        readings: postStartSlice,
        effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
        finding: finding,
        sensorId: sensorId,
        sensorName: sensorName,
        reportedSymptom: reportedSymptom,
        dataSource: dataSource,
        t0Validated: t0Validated,
        isSimulated: isSimulated,
        manualNotes: manualNotes,
      );
    }

    // Caso TENHA atingido o setpoint
    final targetReading = sorted[targetReachedIndex];
    final durationMinutes =
        targetReading.timestamp.difference(startReading.timestamp).inMinutes;
    final testSlice = sorted.sublist(startIndex, targetReachedIndex + 1);

    // 6. Checar se excedeu o prazo máximo normativo
    if (durationMinutes > totalAdjustedAllowedMinutes) {
      final finding = DiagnosticFinding(
        category: FaultCategory.tempoExcedido,
        title: FaultCategory.tempoExcedido.label,
        summary:
            'Tempo limite excedido: O refrigerador levou $durationMinutes minutos para atingir '
            '${profile.targetTemperature}°C (limite calculado pelas normas: $totalAdjustedAllowedMinutes min).',
        probableCauses: const [
          'Condensador obstruído com poeira ou gordura reduzindo troca térmica.',
          'Microventilador do condensador com rotação baixa.',
          'Subcarga leve de gás refrigerante ou filtro secador parcialmente restrito.',
          'Borracha de vedação ressecada ou porta desalinhada.',
        ],
        recommendedActions: const [
          'Realizar limpeza química/ar comprimido na serpentina condensadora.',
          'Testar corrente e rotação do micromotor do condensador.',
          'Verificar sub-resfriamento/pressão na linha de serviço e integridade da gaxeta.',
        ],
        isCritical: false,
      );
      return _buildResult(
        serialNumber: serialNumber,
        modelName: modelName,
        technicianName: technicianName,
        profile: profile,
        status: TestStatus.reprovada,
        reason: finding.summary,
        startReading: startReading,
        endReading: targetReading,
        readings: testSlice,
        effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
        finding: finding,
        sensorId: sensorId,
        sensorName: sensorName,
        reportedSymptom: reportedSymptom,
        dataSource: dataSource,
        t0Validated: t0Validated,
        isSimulated: isSimulated,
        manualNotes: manualNotes,
      );
    }

    // 7. APROVADA (com ou sem choque térmico e auditoria T0)
    final doorOpenCount = testSlice.where((r) => r.doorOpen).length;
    final buffer = StringBuffer();

    if (hadThermalShock) {
      buffer.write(
        'APROVADA COM RECUPERAÇÃO TÉRMICA! Atingiu ${targetReading.temperature.toStringAsFixed(1)}°C '
        'em $durationMinutes minutos mesmo após choque térmico de porta aberta.',
      );
    } else {
      buffer.write(
        'APROVADA com sucesso! Atingiu ${targetReading.temperature.toStringAsFixed(1)}°C '
        'em $durationMinutes minutos (meta calculada pelas normas era até $totalAdjustedAllowedMinutes min).',
      );
      if (doorOpenCount > 0) {
        buffer.write(
          ' ($doorOpenCount evento(s) breve(s) de porta registrada durante o ensaio).',
        );
      }
    }

    if (profile.safetyMinTemperature != null &&
        lowestTemp < profile.safetyMinTemperature!) {
      buffer.write(
        ' ALERTA DE SEGURANÇA: pico mínimo de ${lowestTemp.toStringAsFixed(1)}°C '
        '(abaixo de ${profile.safetyMinTemperature}°C). Calibrar diferencial do controlador.',
      );
    }

    if (!t0Validated) {
      buffer.write(
        ' [Auditoria: Partida com Gabinete Pré-Resfriado a ${initialTemp.toStringAsFixed(1)}°C — recomendado >= ${profile.minStartingAmbientTemp}°C].',
      );
    } else {
      buffer.write(
        ' [Auditoria: Baseline T0 Validado em Repouso Térmico a ${initialTemp.toStringAsFixed(1)}°C].',
      );
    }

    final approvedFinding = DiagnosticFinding(
      category: FaultCategory.sistemaIntegro,
      title: FaultCategory.sistemaIntegro.label,
      summary: buffer.toString(),
      probableCauses: const [
        'Sistema hermético, compressor e circulação de ar dentro dos parâmetros nominais.',
      ],
      recommendedActions: const [
        'Higienizar condensador preventivamente antes da liberação ao cliente.',
        'Confirmar ciclagem automática (cut-out e cut-in) do controlador eletrônico.',
      ],
      isCritical: false,
    );

    return _buildResult(
      serialNumber: serialNumber,
      modelName: modelName,
      technicianName: technicianName,
      profile: profile,
      status: TestStatus.aprovada,
      reason: buffer.toString(),
      startReading: startReading,
      endReading: targetReading,
      readings: testSlice,
      effectiveAllowedMinutes: totalAdjustedAllowedMinutes,
      finding: approvedFinding,
      sensorId: sensorId,
      sensorName: sensorName,
      reportedSymptom: reportedSymptom,
      dataSource: dataSource,
      t0Validated: t0Validated,
      isSimulated: isSimulated,
      manualNotes: manualNotes,
    );
  }

  static DiagnosticFinding _buildCompressorStartFinding({
    required double dropAt15,
    required TestProfile profile,
    String reportedSymptom = '',
  }) {
    final symptomSuffix = reportedSymptom.isNotEmpty
        ? ' Queixa relatada: "$reportedSymptom".'
        : '';
    return DiagnosticFinding(
      category: FaultCategory.falhaPartidaCompressor,
      title: FaultCategory.falhaPartidaCompressor.label,
      summary:
          'Falha de partida ou resposta lenta: a temperatura caiu apenas '
          '${dropAt15.toStringAsFixed(1)}°C nos primeiros 15 min '
          '(mínimo exigido: ${profile.minInitialDrop15}°C). '
          'Verifique relé de partida, protetor térmico ou compressor.$symptomSuffix',
      probableCauses: const [
        'Relé PTC, capacitor de partida ou protetor térmico atuando por sobrecorrente.',
        'Controlador eletrônico / termostato não enviando tensão ao compressor.',
        'Compressor com perda mecânica de compressão (válvulas de palheta) ou travado.',
        'Vazamento severo (falta total de fluido refrigerante no circuito).',
      ],
      recommendedActions: const [
        'Medir corrente de partida/regime com alicate amperímetro e comparar com LRA/FLA.',
        'Testar saída de relé na placa/controlador e continuidade do protetor térmico.',
        'Inspecionar engates elétricos na caixa de ligação do compressor.',
        'Conectar manifold na linha de sucção para confirmar carga de gás.',
      ],
      isCritical: true,
    );
  }

  static DiagnosticFinding _buildFreezeFinding({
    required double minTemp,
    required TestProfile profile,
    required bool isCritical,
  }) {
    return DiagnosticFinding(
      category: FaultCategory.falhaCorteCongelamento,
      title: FaultCategory.falhaCorteCongelamento.label,
      summary:
          'ALERTA CRÍTICO DE CONGELAMENTO: Temperatura caiu para ${minTemp.toStringAsFixed(1)}°C, '
          'violando o limite mínimo seguro de ${profile.safetyMinTemperature}°C do perfil ${profile.displayShort}. '
          'Risco de congelamento ou estouro de embalagens.',
      probableCauses: const [
        'Relé de saída do controlador colado (mantém compressor ligado direto).',
        'Sonda NTC de ambiente descalibrada ou deslocada do retorno de ar.',
        'Setpoint ou diferencial programado errado no controlador.',
      ],
      recommendedActions: const [
        'Aferir resistência ôhmica da sonda NTC em comparação com termômetro calibrado.',
        'Verificar parâmetros de Setpoint (SP) e Diferencial (HY) no controlador.',
        'Testar se o relé do compressor abre ao atingir o corte; substituir se colado.',
      ],
      isCritical: isCritical,
    );
  }

  static DiagnosticFinding _buildStallFinding({
    required double minTemp,
    required double finalTemp,
    required TestProfile profile,
  }) {
    return DiagnosticFinding(
      category: FaultCategory.estagnacaoEvaporadorPorta,
      title: FaultCategory.estagnacaoEvaporadorPorta.label,
      summary:
          'Estagnação ou reaquecimento anômalo: gabinete baixou até ${minTemp.toStringAsFixed(1)}°C '
          'mas subiu/estabilizou em ${finalTemp.toStringAsFixed(1)}°C sem atingir ${profile.targetTemperature}°C.',
      probableCauses: const [
        'Bloqueio de gelo na colmeia do evaporador impedindo circulação de ar frio.',
        'Micromotor do ventilador do evaporador parado ou travado por gelo.',
        'Entrada de ar quente por gaxeta (borracha) danificada ou dreno destampado.',
        'Desarme intermitente do protetor térmico por superaquecimento do compressor.',
      ],
      recommendedActions: const [
        'Abrir carenagem do evaporador e inspecionar formação de gelo e resistência de degelo.',
        'Confirmar funcionamento contínuo do ventilador interno com a porta fechada.',
        'Executar teste da folha de papel em todo o perímetro da gaxeta da porta.',
      ],
      isCritical: true,
    );
  }

  static DiagnosticFinding _buildLowEfficiencyFinding({
    required int durationMinutes,
    required double finalTemp,
    required int allowedMinutes,
    required TestProfile profile,
  }) {
    return DiagnosticFinding(
      category: FaultCategory.baixaEficienciaCargaGas,
      title: FaultCategory.baixaEficienciaCargaGas.label,
      summary:
          'Baixa eficiência de remoção de calor: após $durationMinutes min de ensaio, '
          'o equipamento estabilizou em ${finalTemp.toStringAsFixed(1)}°C sem alcançar ${profile.targetTemperature}°C '
          '(limite normativo: $allowedMinutes min).',
      probableCauses: const [
        'Microvazamento com perda parcial de carga de gás refrigerante.',
        'Filtro secador saturado ou tubo capilar parcialmente obstruído.',
        'Serpentina do condensador suja ou ventilador do condensador com baixa vazão.',
        'Sistema contaminado com umidade ou gases não condensáveis.',
      ],
      recommendedActions: const [
        'Inspecionar marcas de óleo nas soldas e conexões; pressurizar com nitrogênio se necessário.',
        'Limpar completamente o condensador e validar rotação do ventilador.',
        'Trocar filtro secador, realizar vácuo (< 500 mícrons) e recarregar por massa em balança.',
      ],
      isCritical: true,
    );
  }

  static bool _hasProlongedPlateau(
    List<SensorReading> readings, {
    required double targetTemp,
  }) {
    if (readings.length < 4) return false;
    final last = readings.last;
    if (last.temperature <= targetTemp + 3.0) return false;
    final anchorTime = last.timestamp.subtract(const Duration(minutes: 25));
    SensorReading? twentyFiveMinAgo;
    for (final r in readings) {
      if (!r.timestamp.isBefore(anchorTime)) {
        twentyFiveMinAgo = r;
        break;
      }
    }
    if (twentyFiveMinAgo == null) return false;
    final spanMin =
        last.timestamp.difference(twentyFiveMinAgo.timestamp).inMinutes;
    if (spanMin < 20) return false;
    return (twentyFiveMinAgo.temperature - last.temperature) < 0.4;
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

  static int? _findReadingAtOffset(
    List<SensorReading> readings,
    int startIdx,
    Duration offset,
  ) {
    final targetTime = readings[startIdx].timestamp.add(offset);
    for (int i = startIdx; i < readings.length; i++) {
      if (readings[i].timestamp.isAfter(targetTime) ||
          readings[i].timestamp.isAtSameMomentAs(targetTime)) {
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
    required DiagnosticFinding finding,
    required String sensorId,
    required String sensorName,
    required String reportedSymptom,
    required String dataSource,
    required bool t0Validated,
    required bool isSimulated,
    required List<String> manualNotes,
  }) {
    final durationMinutes = math.max(
      1,
      endReading.timestamp.difference(startReading.timestamp).inMinutes,
    );
    final tempDrop = startReading.temperature - endReading.temperature;
    final double coolingRate = tempDrop / durationMinutes;
    final doorOpenEvents = readings.where((r) => r.doorOpen).length;
    final compressorOnCount = readings.where((r) => r.compressorOn).length;
    final double dutyCycle =
        readings.isEmpty ? 1.0 : compressorOnCount / readings.length;

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
      durationMinutes: durationMinutes,
      initialTemp: startReading.temperature,
      finalTemp: endReading.temperature,
      coolingRate: double.parse(coolingRate.toStringAsFixed(2)),
      doorOpenEvents: doorOpenEvents,
      compressorDutyCycle: double.parse(dutyCycle.toStringAsFixed(2)),
      effectiveAllowedMinutes: effectiveAllowedMinutes,
      readings: readings,
      faultCategory: finding.category,
      probableCauses: finding.probableCauses,
      recommendedActions: finding.recommendedActions,
      sensorId: sensorId,
      sensorName: sensorName,
      reportedSymptom: reportedSymptom,
      dataSource: dataSource,
      t0Validated: t0Validated,
      isSimulated: isSimulated,
      synced: false,
      manualNotes: manualNotes,
    );
  }
}
