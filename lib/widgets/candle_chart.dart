import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/price_candle.dart';

/// Compact OHLC candlestick chart; drawing is illustrative, not an orderbook.
class CandleChart extends StatelessWidget {
  const CandleChart({super.key, required this.candles, this.height = 180});
  final List<PriceCandle> candles;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Gerçek mum verisi bekleniyor.',
          style: TextStyle(color: Colors.white54)),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CandlePainter(candles)),
    );
  }
}

class _CandlePainter extends CustomPainter {
  const _CandlePainter(this.source);
  final List<PriceCandle> source;

  @override
  void paint(Canvas canvas, Size size) {
    final candles = source.length > 48 ? source.sublist(source.length - 48) : source;
    if (candles.isEmpty || size.width < 10 || size.height < 10) return;
    final low = candles.map((e) => e.low).reduce(math.min);
    final high = candles.map((e) => e.high).reduce(math.max);
    final range = high - low;
    final floor = low - (range == 0 ? low * .01 : range * .08);
    final ceiling = high + (range == 0 ? high * .01 : range * .08);
    final span = math.max(ceiling - floor, 0.0000000001);
    final top = 10.0, bottom = size.height - 10;
    double y(double price) => top + (ceiling - price) / span * (bottom - top);
    final guideline = Paint()
      ..color = const Color(0xFF344252)
      ..strokeWidth = .7;
    for (var i = 0; i < 4; i++) {
      final yy = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), guideline);
    }

    final pitch = size.width / candles.length;
    for (var i = 0; i < candles.length; i++) {
      final item = candles[i];
      final bullish = item.close >= item.open;
      final paint = Paint()
        ..color = bullish ? const Color(0xFF43D9A3) : const Color(0xFFF27777)
        ..strokeWidth = 1.2;
      final x = (i + .5) * pitch;
      canvas.drawLine(Offset(x, y(item.high)), Offset(x, y(item.low)), paint);
      final topBody = math.min(y(item.open), y(item.close));
      final bottomBody = math.max(y(item.open), y(item.close));
      final body = math.max(1.5, bottomBody - topBody);
      final width = math.max(1.5, math.min(pitch * .68, 9.0));
      canvas.drawRect(
        Rect.fromLTWH(x - width / 2, topBody, width, body),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      !identical(source, oldDelegate.source);
}
