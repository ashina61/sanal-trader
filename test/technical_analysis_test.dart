import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/price_candle.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/technical_analysis.dart';
import 'package:sanal_trader/services/learning_bot.dart';

CoinQuote technicalQuote(List<double> close, {
  List<PriceCandle> candles = const [],
}) => CoinQuote(
  id: 'bitcoin',
  name: 'Bitcoin',
  symbol: 'BTC',
  priceTry: close.last,
  change24h: 2,
  updatedAt: DateTime.now().toUtc(),
  sparkline: close,
  candles: candles,
  volume24hUsdt: 100000000,
);

void main() {
  test('Insufficient data does not yield fabricated RSI or trend signal', () {
    final result = analyzeTechnical(technicalQuote([100, 101, 102]));
    expect(result.ready, isFalse);
    expect(result.decisionLabel, 'VERİ YETERSİZ');
  });

  test('Steady uptrend has rising EMA20/50 and positive MACD', () {
    final prices = List<double>.generate(168, (i) => 100 + i * .5);
    final r = analyzeTechnical(technicalQuote(prices));
    expect(r.ready, isTrue);
    expect(r.trend, TrendDirection.rising);
    expect(r.ema20, greaterThan(r.ema50));
    expect(r.macdHistogram, greaterThan(0));
    expect(r.rsi, greaterThan(70));
    expect(r.warnings, isNotEmpty);
  });

  test('Flat trend produces neutral RSI instead of division by zero', () {
    final prices = List<double>.filled(168, 100);
    final r = analyzeTechnical(technicalQuote(prices));
    expect(r.ready, isTrue);
    expect(r.rsi, closeTo(50, .01));
    expect(r.trend, TrendDirection.sideways);
    expect(r.score.isFinite, isTrue);
  });

  test('Downtrend reads selling pressure and warns in weak regime', () {
    final prices = List<double>.generate(168, (i) => 300 - i * .5);
    final r = analyzeTechnical(technicalQuote(prices));
    expect(r.trend, TrendDirection.falling);
    expect(r.ema20, lessThan(r.ema50));
    expect(r.score, lessThan(0));
  });

  test('Only closed hourly Binance candle enters OHLCV model', () {
    final now = DateTime.now().toUtc();
    List<dynamic> row(int closingTime) => [
      closingTime - 3600000,
      '100', '106', '98', '104', '500',
      closingTime, '1250000',
    ];
    final closed = PriceCandle.fromBinanceKline(
      row(now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch),
      2.0, now: now,
    );
    expect(closed, isNotNull);
    expect(closed!.high, 212);
    expect(closed.volumeUsdt, 1250000);
    expect(PriceCandle.fromBinanceKline(
      row(now.add(const Duration(minutes: 1)).millisecondsSinceEpoch),
      2.0, now: now,
    ), isNull);
  });

  test('Candlestick pattern detection uses actual open/high/low/close', () {
    final prices = List<double>.generate(168, (i) => 100 + .1 * i);
    final current = DateTime.now().toUtc();
    final candles = List<PriceCandle>.generate(25, (i) {
      final value = prices[prices.length - 25 + i];
      return PriceCandle(time: current.subtract(Duration(hours: 25 - i)),
        open: value - .1, high: value + .3, low: value - .3,
        close: value, volumeUsdt: 1000000);
    });
    candles[candles.length - 2] = PriceCandle(
      time: current.subtract(const Duration(hours: 2)),
      open: 115.5, high: 116, low: 114.5, close: 115.0,
      volumeUsdt: 1000000,
    );
    candles[candles.length - 1] = PriceCandle(
      time: current.subtract(const Duration(hours: 1)),
      open: 114.8, high: 117.5, low: 114.4, close: 117.2,
      volumeUsdt: 1800000,
    );
    final r = analyzeTechnical(technicalQuote(prices, candles: candles));
    expect(r.pattern, CandlePattern.bullishEngulfing);
    expect(r.volumeRatio, greaterThan(1));
    expect(r.atrPct, greaterThan(0));
  });

  test('Drawdown pauses new buys but retains exit logic', () {
    final q = technicalQuote(List<double>.generate(168, (i) => 80 + i * .1));
    final initial = BotState.initial().copyWith(
      enabled: true,
      peakEquityTry: 900,
    );
    final paused = planBotOrder(
      state: initial,
      wallet: Portfolio.fresh(),
      quotes: {'bitcoin': q},
    );
    expect(paused, isNull);
  });
}
