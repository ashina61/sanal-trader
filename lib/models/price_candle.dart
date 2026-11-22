/// A completed one-hour exchange OHLCV candle.
/// These values are expressed in TRY using the latest USDT/TRY conversion
/// rate, NOT historical hourly TRY conversion rates.
class PriceCandle {
  const PriceCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volumeUsdt,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volumeUsdt;

  bool get valid => open.isFinite && high.isFinite && low.isFinite &&
      close.isFinite && volumeUsdt.isFinite && volumeUsdt >= 0 &&
      low > 0 && high >= low && open >= low && open <= high &&
      close >= low && close <= high;

  static PriceCandle? fromBinanceKline(dynamic value, double tryRate, {DateTime? now}) {
    if (value is! List || value.length < 8 || !tryRate.isFinite || tryRate <= 0) {
      return null;
    }
    final closeTime = value[6];
    if (closeTime is! num) return null;
    final currentTime = (now ?? DateTime.now()).toUtc();
    final time = DateTime.fromMillisecondsSinceEpoch(closeTime.toInt(), isUtc: true);
    if (time.isAfter(currentTime)) return null; // Ignore unclosed candles.
    double? parse(dynamic x) => double.tryParse(x.toString());
    final o = parse(value[1]);
    final h = parse(value[2]);
    final l = parse(value[3]);
    final c = parse(value[4]);
    final v = parse(value[7]);
    if (o == null || h == null || l == null || c == null || v == null) return null;
    final candle = PriceCandle(
      time: time,
      open: o * tryRate,
      high: h * tryRate,
      low: l * tryRate,
      close: c * tryRate,
      volumeUsdt: v,
    );
    return candle.valid ? candle : null;
  }
}
