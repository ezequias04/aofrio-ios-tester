import '../models/sensor_reading.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import 'diagnostic_engine.dart';

/// Fachada de compatibilidade para o motor de análise pull-down adaptativo.
class PullDownAnalyzer {
  static TestResult analyze({
    required String serialNumber,
    required String modelName,
    required String technicianName,
    required TestProfile profile,
    required List<SensorReading> readings,
  }) {
    return DiagnosticEngine.diagnose(
      serialNumber: serialNumber,
      modelName: modelName,
      technicianName: technicianName,
      profile: profile,
      readings: readings,
      allowPartial: false,
    );
  }
}
