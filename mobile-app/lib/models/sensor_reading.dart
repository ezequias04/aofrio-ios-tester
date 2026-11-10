/// Representa uma única leitura registrada na memória do sensor AoFrio
class SensorReading {
  final DateTime timestamp;
  final double temperature; // em graus Celsius
  final bool doorOpen;       // verdadeiro se a porta estava aberta
  final bool compressorOn;   // verdadeiro se o compressor estava em funcionamento

  const SensorReading({
    required this.timestamp,
    required this.temperature,
    this.doorOpen = false,
    this.compressorOn = true,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'temperature': temperature,
    'doorOpen': doorOpen,
    'compressorOn': compressorOn,
  };

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
    timestamp: DateTime.parse(json['timestamp']),
    temperature: (json['temperature'] as num).toDouble(),
    doorOpen: json['doorOpen'] ?? false,
    compressorOn: json['compressorOn'] ?? true,
  );
}
