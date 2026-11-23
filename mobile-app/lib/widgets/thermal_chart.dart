import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';

/// Gráfico completo interativo da curva de pull-down (°C x minutos decorridos).
class ThermalCurveChart extends StatelessWidget {
  final List<SensorReading> readings;
  final double targetTemp;
  final double? safetyMinTemp;
  final Color accentColor;
  final double height;

  const ThermalCurveChart({
    super.key,
    required this.readings,
    required this.targetTemp,
    this.safetyMinTemp,
    this.accentColor = AppColors.cryo,
    this.height = 230,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.show_chart_rounded, size: 32, color: AppColors.muted),
              const SizedBox(height: 8),
              Text(
                readings.isEmpty
                    ? 'Aguardando as primeiras leituras térmicas...'
                    : '1 leitura capturada (${readings.first.temperature.toStringAsFixed(1)}°C). A curva será desenhada na próxima amostra.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final start = readings.first.timestamp;
    final spots = <FlSpot>[];
    var minTemp = readings.first.temperature;
    var maxTemp = readings.first.temperature;

    for (final r in readings) {
      final mins = r.timestamp.difference(start).inSeconds / 60.0;
      if (r.temperature < minTemp) minTemp = r.temperature;
      if (r.temperature > maxTemp) maxTemp = r.temperature;
      spots.add(FlSpot(mins, r.temperature));
    }

    final double maxX = math.max(1.0, spots.last.x);
    double minY = math.min(minTemp, targetTemp);
    if (safetyMinTemp != null) {
      minY = math.min(minY, safetyMinTemp!);
    }
    minY = (minY - 3).floorToDouble();
    final double maxY = (math.max(maxTemp, targetTemp) + 3).ceilToDouble();
    final double spanY = math.max(4.0, maxY - minY);
    final double yInterval = (spanY / 4).clamp(2.0, 20.0).ceilToDouble();
    final double xInterval = (maxX / 4).clamp(1.0, 120.0).ceilToDouble();

    final referenceLines = <HorizontalLine>[
      HorizontalLine(
        y: targetTemp,
        color: AppColors.approved,
        strokeWidth: 1.6,
        dashArray: const [6, 4],
        label: HorizontalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          padding: const EdgeInsets.only(right: 4, bottom: 2),
          style: const TextStyle(
            color: AppColors.approved,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
          labelResolver: (_) => 'Meta ${targetTemp.toStringAsFixed(1)}°C',
        ),
      ),
      if (safetyMinTemp != null)
        HorizontalLine(
          y: safetyMinTemp!,
          color: AppColors.fault.withValues(alpha: 0.75),
          strokeWidth: 1.3,
          dashArray: const [4, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.bottomRight,
            padding: const EdgeInsets.only(right: 4, top: 2),
            style: const TextStyle(
              color: AppColors.fault,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            labelResolver: (_) => 'Limite ${safetyMinTemp!.toStringAsFixed(1)}°C',
          ),
        ),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          extraLinesData: ExtraLinesData(horizontalLines: referenceLines),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.line,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.obsidian,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)}°C\n${spot.x.toStringAsFixed(0)} min',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: yInterval,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}°',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: xInterval,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}m',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              gradient: LinearGradient(
                colors: [AppColors.indigo, accentColor],
              ),
              barWidth: 3.5,
              isCurved: true,
              curveSmoothness: 0.2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor.withValues(alpha: 0.18),
                    accentColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sparkline compacta não-interativa para cards ao vivo da bancada.
class ThermalSparkline extends StatelessWidget {
  final List<SensorReading> readings;
  final Color color;
  final double height;

  const ThermalSparkline({
    super.key,
    required this.readings,
    this.color = AppColors.cryo,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    final start = readings.first.timestamp;
    final spots = readings
        .map((r) => FlSpot(
              r.timestamp.difference(start).inSeconds / 60.0,
              r.temperature,
            ))
        .toList();

    final maxX = math.max(0.5, spots.last.x);
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    return SizedBox(
      height: height,
      child: IgnorePointer(
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: minY - 1,
            maxY: maxY + 1,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: color,
                barWidth: 2.5,
                isCurved: true,
                curveSmoothness: 0.25,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
