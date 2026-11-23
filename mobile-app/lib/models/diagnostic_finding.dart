/// Categoria raiz da assinatura térmica diagnosticada no equipamento.
enum FaultCategory {
  sistemaIntegro,
  falhaPartidaCompressor,
  baixaEficienciaCargaGas,
  estagnacaoEvaporadorPorta,
  falhaCorteCongelamento,
  tempoExcedido,
  ensaioInterrompido,
}

extension FaultCategoryInfo on FaultCategory {
  String get code => name;

  String get label {
    switch (this) {
      case FaultCategory.sistemaIntegro:
        return 'Sistema Frigorífico Íntegro';
      case FaultCategory.falhaPartidaCompressor:
        return 'Falha de Partida ou Compressão';
      case FaultCategory.baixaEficienciaCargaGas:
        return 'Baixa Eficiência / Carga de Gás';
      case FaultCategory.estagnacaoEvaporadorPorta:
        return 'Estagnação / Bloqueio ou Vedação';
      case FaultCategory.falhaCorteCongelamento:
        return 'Risco / Falha de Corte (Congelamento)';
      case FaultCategory.tempoExcedido:
        return 'Pull-Down Lento (Tempo Excedido)';
      case FaultCategory.ensaioInterrompido:
        return 'Ensaio Interrompido Antes da Meta';
    }
  }

  static FaultCategory fromString(String? raw) {
    if (raw == null || raw.isEmpty) return FaultCategory.sistemaIntegro;
    return FaultCategory.values.firstWhere(
      (c) => c.name == raw,
      orElse: () => FaultCategory.sistemaIntegro,
    );
  }
}

/// Fase em tempo real de um diagnóstico na bancada.
enum DiagnosticPhase {
  aguardandoSinal,
  auditoriaInicial,
  verificandoPartida,
  emResfriamento,
  metaAtingida,
  alertaCongelamento,
}

extension DiagnosticPhaseLabel on DiagnosticPhase {
  String get label {
    switch (this) {
      case DiagnosticPhase.aguardandoSinal:
        return 'Aguardando sinal';
      case DiagnosticPhase.auditoriaInicial:
        return 'Auditoria T0';
      case DiagnosticPhase.verificandoPartida:
        return 'Partida (0-15m)';
      case DiagnosticPhase.emResfriamento:
        return 'Em pull-down';
      case DiagnosticPhase.metaAtingida:
        return 'Meta atingida';
      case DiagnosticPhase.alertaCongelamento:
        return 'Alerta térmico';
    }
  }
}

enum LiveHealth {
  excelente,
  normal,
  atencao,
  critico,
}

/// Achado detalhado de diagnóstico com causas e checklist de oficina.
class DiagnosticFinding {
  final FaultCategory category;
  final String title;
  final String summary;
  final List<String> probableCauses;
  final List<String> recommendedActions;
  final bool isCritical;

  const DiagnosticFinding({
    required this.category,
    required this.title,
    required this.summary,
    required this.probableCauses,
    required this.recommendedActions,
    this.isCritical = false,
  });

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'title': title,
        'summary': summary,
        'probableCauses': probableCauses,
        'recommendedActions': recommendedActions,
        'isCritical': isCritical,
      };

  factory DiagnosticFinding.fromJson(Map<String, dynamic> json) {
    return DiagnosticFinding(
      category: FaultCategoryInfo.fromString(json['category']?.toString()),
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      probableCauses: (json['probableCauses'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      recommendedActions:
          (json['recommendedActions'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      isCritical: json['isCritical'] == true,
    );
  }
}

/// Fotografia instantânea do diagnóstico durante uma sessão ao vivo na bancada.
class LiveDiagnosticSnapshot {
  final DiagnosticPhase phase;
  final LiveHealth health;
  final String headline;
  final String subtext;
  final double? initialTemp;
  final double? currentTemp;
  final double? minTemp;
  final double? maxTemp;
  final double deltaTemp;
  final double? dropAt15Min;
  final double recentCoolingRate; // °C/min positivo quando está caindo
  final double averageCoolingRate; // °C/min positivo quando caiu
  final int? estimatedMinutesToTarget;
  final bool targetReached;
  final int? targetReachedMinutes;
  final bool t0Validated;
  final bool antiFreezeViolation;
  final double progressRatio;
  final DiagnosticFinding? preliminaryFinding;

  const LiveDiagnosticSnapshot({
    required this.phase,
    required this.health,
    required this.headline,
    required this.subtext,
    this.initialTemp,
    this.currentTemp,
    this.minTemp,
    this.maxTemp,
    this.deltaTemp = 0.0,
    this.dropAt15Min,
    this.recentCoolingRate = 0.0,
    this.averageCoolingRate = 0.0,
    this.estimatedMinutesToTarget,
    this.targetReached = false,
    this.targetReachedMinutes,
    this.t0Validated = true,
    this.antiFreezeViolation = false,
    this.progressRatio = 0.0,
    this.preliminaryFinding,
  });
}
