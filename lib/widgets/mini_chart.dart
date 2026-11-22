import 'dart:math' as math;
import 'package:flutter/material.dart';

class MiniChart extends StatelessWidget {
  const MiniChart({super.key, required this.prices, required this.positive, this.height = 68});
  final List<double> prices;
  final bool positive;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (prices.length < 2) {
      return SizedBox(height: height, child: const Center(child: Text('Grafik verisi yok')));
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(prices, positive ? const Color(0xFF44E5AB) : const Color(0xFFFF796F)),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = math.max(0.0000000001, maxValue - minValue);
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = index / (values.length - 1) * size.width;
      final y = 6 + (1 - (values[index] - minValue) / span) * (size.height - 12);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.values != values;
}
