import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Novo símbolo "Thermal Pulse Shield / Cryo Gauge" da identidade ISO Test.
class IsoLogo extends StatelessWidget {
  final double size;
  final bool showBorder;

  const IsoLogo({
    super.key,
    this.size = 40,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: showBorder
            ? Border.all(color: AppColors.indigoBright.withValues(alpha: 0.45), width: 1.5)
            : null,
      ),
      child: CustomPaint(
        painter: _IsoLogoPainter(),
      ),
    );
  }
}

class _IsoLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final cy = s / 2;

    // Aro de calibração quebrado (Indigo + Cryo Sky)
    final ringRect = Rect.fromCircle(center: Offset(cx, cy), radius: s * 0.36);
    final strokeW = math.max(1.8, s * 0.068);

    final indigoArcPaint = Paint()
      ..color = AppColors.indigoBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final cryoArcPaint = Paint()
      ..color = AppColors.cryoBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(ringRect, math.pi * 0.80, math.pi * 1.28, false, indigoArcPaint);
    canvas.drawArc(ringRect, math.pi * 0.18, math.pi * 0.44, false, cryoArcPaint);

    // Linha tracejada da meta (Emerald)
    final targetY = cy + s * 0.145;
    final targetLinePaint = Paint()
      ..color = AppColors.approvedBright.withValues(alpha: 0.5)
      ..strokeWidth = math.max(1.0, s * 0.025);
    canvas.drawLine(
      Offset(cx - s * 0.22, targetY),
      Offset(cx + s * 0.22, targetY),
      targetLinePaint,
    );

    // Curva descendente de pull-down
    final p0 = Offset(cx - s * 0.21, cy - s * 0.15);
    final p3 = Offset(cx + s * 0.19, targetY);
    final curvePath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(
        cx - s * 0.06,
        cy - s * 0.13,
        cx + s * 0.04,
        cy + s * 0.12,
        p3.dx,
        p3.dy,
      );

    final curvePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          AppColors.amber,
          AppColors.indigoBright,
          AppColors.cryoBright,
          AppColors.approvedBright,
        ],
      ).createShader(Rect.fromPoints(p0, p3))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, s * 0.085)
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(curvePath, curvePaint);

    // Nó inicial T0 quente (Amber)
    canvas.drawCircle(
      p0,
      s * 0.062,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      p0,
      s * 0.042,
      Paint()..color = AppColors.amber,
    );

    // Nó final estabilizado na meta (Emerald + halo)
    canvas.drawCircle(
      p3,
      s * 0.11,
      Paint()..color = AppColors.approvedBright.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      p3,
      s * 0.074,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      p3,
      s * 0.052,
      Paint()..color = AppColors.approvedBright,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
