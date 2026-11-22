import 'dart:math' as math;
import '../models/backtest_summary.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import 'learning_bot.dart';
import 'technical_analysis.dart';

/// Compare a FIXED already-trained strategy with fee-inclusive buy-and-hold
/// over the last 24 hourly closes (strictly after its training window).
///
/// A virtual reference account of 100 units PER coin is used only inside this
/// evaluator. It NEVER writes to the user's 650 TRY wallet or order history.
/// Trades execute at the *observed hourly close*, with 0.1% paper trading fee
/// plus assumed 0.05% slippage per side. No future candle may affect a signal.
BacktestSummary? walkForwardBacktest(
  Iterable<CoinQuote> source, {
  required List<double> weights,
  DateTime? now,
}) {
  if (weights.length != 3 || weights.any((w) => !w.isFinite || w <= 0)) {
    return null;
  }
  final coins = source.where((q) =>
      q.sparkline.length >= 96 &&
      q.sparkline.every((p) => p.isFinite && p > 0)).toList();
  if (coins.length < 3) return null;
  final length = coins.map((c) => c.sparkline.length).reduce(math.min);
  if (length < 96) return null;

  const notional = 100.0;
  const slippage = 0.0005;
  const roundTripSideCost = tradingFeeRate + slippage;
  final firstHoldout = length - 24;
  var closedTrades = 0, wins = 0;
  var totalNet = 0.0, totalBaseline = 0.0;
  final perHourReturns = List<double>.filled(24, 0);

  for (final coin in coins) {
    // Trim to a shared, timestamp-compatible horizon, no forward leakage.
    final prices = coin.sparkline.sublist(coin.sparkline.length - length);
    var cash = notional, units = 0.0, cost = 0.0;
    var boughtAtIndex = -1;
    final baselineUnits = notional *
        (1 - roundTripSideCost) / prices[firstHoldout];

    for (var i = firstHoldout; i < length; i++) {
      final price = prices[i];
      final change24 = (price / prices[i - 24] - 1) * 100;
      final point = CoinQuote(
        id: coin.id, symbol: coin.symbol, name: coin.name,
        priceTry: price, change24h: change24,
        updatedAt: (now ?? DateTime.now()).toUtc(),
        // Only history known at the current test instant is visible.
        sparkline: prices.sublist(0, i + 1),
        volume24hUsdt: coin.volume24hUsdt,
      );
      final technical = analyzeTechnical(point);
      final score = botScore(point, weights) * .65 +
          technical.score * .35;

      // Cost-aware single-position, long-only strategy, no hindsight fills.
      if (units <= 0 && i < length - 1 &&
          technical.ready &&
          technical.trend != TrendDirection.falling &&
          technical.score >= .18 && score >= .45) {
        cost = cash;
        units = cash * (1 - roundTripSideCost) / price;
        cash = 0;
        boughtAtIndex = i;
      } else if (units > 0 &&
          i > boughtAtIndex &&
          (score < 0 || technical.score <= -.3 ||
              price * units < cost * .94 ||
              price * units > cost * 1.08 ||
              i == length - 1)) {
        cash = units * price * (1 - roundTripSideCost);
        units = 0;
        closedTrades++;
        if (cash > cost) wins++;
      }
      perHourReturns[i - firstHoldout] += (cash + units * price) / notional;
    }

    // End-of-period liquidation, always costs the modeled exit fee.
    if (units > 0) {
      cash = units * prices.last * (1 - roundTripSideCost);
      closedTrades++;
      if (cash > cost) wins++;
      // Correct the final equity for the terminal liquidation cost.
      perHourReturns[23] -=
          units * prices.last * roundTripSideCost / notional;
    }
    totalNet += cash / notional - 1;
    totalBaseline += baselineUnits * prices.last *
        (1 - roundTripSideCost) / notional - 1;
  }

  var peak = 1.0, maxDrawdown = 0.0;
  for (final value in perHourReturns) {
    final equity = value / coins.length;
    peak = math.max(peak, equity);
    maxDrawdown = math.max(maxDrawdown, (1 - equity / peak).clamp(0.0, 1.0).toDouble());
  }

  return BacktestSummary(
    coins: coins.length,
    closedTrades: closedTrades,
    winningTrades: wins,
    strategyReturnPct: totalNet / coins.length * 100,
    buyHoldReturnPct: totalBaseline / coins.length * 100,
    maxDrawdownPct: maxDrawdown * 100,
    evaluatedAt: (now ?? DateTime.now()).toUtc(),
  );
}
