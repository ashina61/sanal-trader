import 'dart:math' as math;
import '../models/coin_quote.dart';
import '../models/price_candle.dart';

enum TrendDirection { rising, falling, sideways }

enum CandlePattern { none, bullishEngulfing, bearishEngulfing, hammer, shootingStar }

/// Interprets historical price/volume context without pretending certainty.
class TechnicalReport {
  const TechnicalReport({
    required this.ready,
    required this.reason,
    required this.trend,
    required this.rsi,
    required this.ema20,
    required this.ema50,
    required this.macd,
    required this.macdSignal,
    required this.macdHistogram,
    required this.support,
    required this.resistance,
    required this.volatility24hPct,
    required this.atrPct,
    required this.volumeRatio,
    required this.pattern,
    required this.score,
    required this.reasons,
    required this.warnings,
  });

  final bool ready;
  final String reason;
  final TrendDirection trend;
  final double rsi, ema20, ema50, macd, macdSignal, macdHistogram;
  final double support, resistance, volatility24hPct, atrPct, volumeRatio;
  final CandlePattern pattern;
  final double score;
  final List<String> reasons;
  final List<String> warnings;

  bool get riskElevated => volatility24hPct > 9 ||
      atrPct > 5 || (rsi > 79) || (rsi < 20);

  String get trendLabel => switch (trend) {
    TrendDirection.rising => 'Yükseliş eğilimi',
    TrendDirection.falling => 'Düşüş eğilimi',
    TrendDirection.sideways => 'Yatay / kararsız',
  };

  String get patternLabel => switch (pattern) {
    CandlePattern.none => 'Net mum formasyonu yok',
    CandlePattern.bullishEngulfing => 'Yutan boğa mumu',
    CandlePattern.bearishEngulfing => 'Yutan ayı mumu',
    CandlePattern.hammer => 'Çekiç / alttan tepki',
    CandlePattern.shootingStar => 'Üst fitil / satış baskısı',
  };

  String get decisionLabel {
    if (!ready) return 'VERİ YETERSİZ';
    if (riskElevated && score < 0.6) return 'RİSKLİ / BEKLE';
    if (score >= 0.35) return 'ALIM ADAYI';
    if (score <= -0.35) return 'SATIŞ BASKISI';
    return 'BEKLE / TAKİP ET';
  }

  static const insufficient = TechnicalReport(
    ready: false, reason: 'En az 60 geçerli saatlik kapanış gerekli',
    trend: TrendDirection.sideways,
    rsi: 50, ema20: 0, ema50: 0, macd: 0, macdSignal: 0,
    macdHistogram: 0, support: 0, resistance: 0,
    volatility24hPct: 0, atrPct: 0, volumeRatio: 0,
    pattern: CandlePattern.none, score: 0,
    reasons: [], warnings: ['İleri teknik yorum için geçmiş fiyat bekleniyor'],
  );
}

List<double> _emaSeries(List<double> source, int period) {
  final alpha = 2 / (period + 1);
  if (source.isEmpty) return [];
  final out = <double>[source.first];
  for (var i = 1; i < source.length; i++) {
    out.add(source[i] * alpha + out.last * (1 - alpha));
  }
  return out;
}

double _rsi(List<double> closes, int period) {
  if (closes.length <= period) return 50;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final diff = closes[i] - closes[i - 1];
    if (diff > 0) { gain += diff; } else { loss -= diff; }
  }
  gain /= period;
  loss /= period;
  for (var i = period + 1; i < closes.length; i++) {
    final delta = closes[i] - closes[i - 1];
    gain = (gain * (period - 1) + math.max(0.0, delta)) / period;
    loss = (loss * (period - 1) + math.max(0.0, -delta)) / period;
  }
  if (gain == 0 && loss == 0) return 50;
  if (loss == 0) return 100;
  return 100 - 100 / (1 + gain / loss);
}

CandlePattern _pattern(List<PriceCandle> candles) {
  if (candles.length < 2) return CandlePattern.none;
  final previous = candles[candles.length - 2];
  final last = candles.last;
  final range = last.high - last.low;
  if (range <= 0) return CandlePattern.none;
  final bullish = last.close > last.open;
  final body = (last.close - last.open).abs();
  final topWick = last.high - math.max(last.close, last.open);
  final bottomWick = math.min(last.close, last.open) - last.low;
  if (previous.close < previous.open && bullish &&
      last.open <= previous.close && last.close >= previous.open &&
      body > range * .30) return CandlePattern.bullishEngulfing;
  if (previous.close > previous.open && !bullish &&
      last.open >= previous.close && last.close <= previous.open &&
      body > range * .30) return CandlePattern.bearishEngulfing;
  if (bottomWick > body * 2 && bottomWick > topWick * 2 &&
      body > range * .05) return CandlePattern.hammer;
  if (topWick > body * 2 && topWick > bottomWick * 2 &&
      body > range * .05) return CandlePattern.shootingStar;
  return CandlePattern.none;
}

TechnicalReport analyzeTechnical(CoinQuote quote) {
  final closes = quote.sparkline;
  if (closes.length < 60 || closes.any((p) => !p.isFinite || p <= 0)) {
    return TechnicalReport.insufficient;
  }
  // Last point may be latest spot. Closed candles are not fabricated.
  final ema20 = _emaSeries(closes, 20).last;
  final ema50 = _emaSeries(closes, 50).last;
  final e12 = _emaSeries(closes, 12);
  final e26 = _emaSeries(closes, 26);
  final macdLine = List<double>.generate(closes.length, (i) => e12[i] - e26[i]);
  final macdSignal = _emaSeries(macdLine, 9).last;
  final macd = macdLine.last;
  final hist = macd - macdSignal;
  final rsi = _rsi(closes, 14);

  // Past 48h levels exclude today's newest live point.
  final history = closes.sublist(math.max(0, closes.length - 49), closes.length - 1);
  final support = history.reduce(math.min);
  final resistance = history.reduce(math.max);
  final returns = <double>[];
  for (var i = math.max(1, closes.length - 24); i < closes.length; i++) {
    returns.add(math.log(closes[i] / closes[i - 1]));
  }
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance = returns.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2).toDouble()) / returns.length;
  final vol = math.sqrt(variance) * math.sqrt(24) * 100;

  final candles = quote.candles;
  var atrPct = 0.0;
  var volumeRatio = 0.0;
  if (candles.length >= 22) {
    final trueRanges = <double>[];
    for (var i = candles.length - 14; i < candles.length; i++) {
      final candle = candles[i];
      final priorClose = candles[i - 1].close;
      trueRanges.add(math.max(candle.high - candle.low,
          math.max((candle.high - priorClose).abs(), (candle.low - priorClose).abs())));
    }
    atrPct = trueRanges.reduce((a, b) => a + b) / 14 / quote.priceTry * 100;
    final recent = candles.sublist(candles.length - 21, candles.length - 1);
    final baseVolume = recent.fold<double>(0, (s, c) => s + c.volumeUsdt) / recent.length;
    if (baseVolume > 0) volumeRatio = candles.last.volumeUsdt / baseVolume;
  }

  final isUp = closes.last >= ema20 && ema20 > ema50 * 1.001;
  final isDown = closes.last < ema20 && ema20 < ema50 * .999;
  final trend = isUp ? TrendDirection.rising : (isDown ? TrendDirection.falling : TrendDirection.sideways);
  final pattern = _pattern(candles);
  final reasons = <String>[];
  final warnings = <String>[];
  var score = 0.0;
  if (isUp) { score += .27; reasons.add('Fiyat EMA20 üzerinde; EMA20, EMA50 üzerinde'); }
  else if (isDown) { score -= .27; reasons.add('Fiyat EMA20 altında; EMA20, EMA50 altında'); }
  else { reasons.add('EMA20/EMA50 net yön göstermiyor'); }
  if (hist > 0 && macd > macdSignal) {
    score += .20;
    reasons.add('MACD histogramı pozitif: yukarı momentum');
  } else if (hist < 0 && macd < macdSignal) {
    score -= .20;
    reasons.add('MACD histogramı negatif: aşağı momentum');
  }
  if (rsi >= 52 && rsi <= 68) { score += .12; reasons.add('RSI dengeli yükseliş bölgesinde'); }
  if (rsi <= 43 && rsi >= 30) { score -= .12; reasons.add('RSI zayıf momentum gösteriyor'); }
  if (rsi > 75) { score -= .15; warnings.add('RSI yüksek: aşırı alım / geri çekilme riski'); }
  if (rsi < 25) { warnings.add('RSI düşük: aşırı satım, tek başına alış işareti değil'); }
  if (closes.last > resistance * 1.002) {
    score += .20; reasons.add('Önceki 48 saatlik direncin üzerinde kapanış/fiyat');
  }
  if (closes.last < support * .998) {
    score -= .20; reasons.add('Önceki 48 saatlik desteğin altına sarkma');
  }
  if (volumeRatio >= 1.5) {
    if (score > 0) score += .12; else if (score < 0) score -= .12;
    reasons.add('Son tamamlanan saatte hacim artışı');
  } else if (volumeRatio > 0 && volumeRatio < .6) {
    warnings.add('Düşük son saat hacmi: sinyal teyidi zayıf');
  } else if (candles.isEmpty) {
    warnings.add('OHLCV gelmedi: mum ve hacim yorumu yapılamıyor');
  }
  switch (pattern) {
    case CandlePattern.bullishEngulfing:
    case CandlePattern.hammer:
      score += .09; reasons.add('Pozitif yönde mum formasyonu');
    case CandlePattern.bearishEngulfing:
    case CandlePattern.shootingStar:
      score -= .09; reasons.add('Negatif yönde mum formasyonu');
    case CandlePattern.none:
      break;
  }
  if (vol > 9) {warnings.add('24 saatlik oynaklık yüksek; küçük pozisyon gerekli');}
  if (atrPct > 5) {warnings.add('ATR yüksek: mum aralıkları geniş');}
  return TechnicalReport(
    ready: true, reason: 'Saatlik veriden analiz',
    trend: trend, rsi: rsi, ema20: ema20, ema50: ema50,
    macd: macd, macdSignal: macdSignal, macdHistogram: hist,
    support: support, resistance: resistance,
    volatility24hPct: vol, atrPct: atrPct, volumeRatio: volumeRatio,
    pattern: pattern, score: score.clamp(-1.0, 1.0).toDouble(),
    reasons: reasons, warnings: warnings,
  );
}
