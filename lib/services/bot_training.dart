import 'dart:math' as math;
import '../models/coin_quote.dart';
import 'learning_bot.dart';

/// Time-ordered offline study. Last 24 hourly observations are untouched
/// holdout data. No live orders, API keys or fake profit calculations.
class BotTrainingResult {
  const BotTrainingResult({
    required this.weights,
    required this.trainingExamples,
    required this.holdoutExamples,
    required this.holdoutCorrect,
    required this.baselineCorrect,
    required this.coins,
  });
  final List<double> weights;
  final int trainingExamples;
  final int holdoutExamples;
  final int holdoutCorrect;
  final int baselineCorrect;
  final int coins;
  double get holdoutAccuracy => holdoutExamples == 0 ? 0 : holdoutCorrect / holdoutExamples;
  double get baselineAccuracy => holdoutExamples == 0 ? 0 : baselineCorrect / holdoutExamples;
}

/// Returns null rather than inventing training results from missing history.
/// Samples use only observations through hour i to predict hour i+1.
BotTrainingResult? trainHistoricalBot(
  Iterable<CoinQuote> quotes, {
  List<double>? seedWeights,
}) {
  final series = quotes
      .where((q) => q.sparkline.length >= 96)
      .map((q) => q.sparkline)
      .where((p) => p.every((v) => v.isFinite && v > 0))
      .toList();
  if (series.length < 3) return null;
  final length = series.map((p) => p.length).reduce(math.min);
  if (length < 96) return null;
  final trainEnd = length - 24; // last 24h is holdout
  if (trainEnd < 60) return null;

  final initial = seedWeights == null || seedWeights.length != 3
      ? <double>[1 / 3, 1 / 3, 1 / 3]
      : List<double>.from(seedWeights);
  if (initial.any((w) => !w.isFinite || w <= 0)) return null;
  final total = initial.reduce((a, b) => a + b);
  final weights = initial.map((w) => w / total).toList();

  var trainingExamples = 0;
  var holdoutExamples = 0;
  var holdoutCorrect = 0;
  var baselineCorrect = 0;

  // Aggregate all same-hour examples BEFORE updating. Avoids cross-coin
  // future leakage when a different asset's next-hour return is known.
  for (var i = 30; i < length - 1; i++) {
    final grad = <double>[0, 0, 0];
    var active = 0;
    for (final prices in series) {
      final current = prices[i];
      final next = prices[i + 1];
      final change = next / current - 1;
      if (change.abs() < 0.001) continue; // noise; no positive label
      final dayChange = (current / prices[i - 24] - 1) * 100;
      final point = CoinQuote(
        id: 'history', symbol: 'H', name: 'History',
        priceTry: current, change24h: dayChange,
        updatedAt: DateTime.now().toUtc(),
        sparkline: prices.sublist(0, i + 1),
      );
      final signals = botSignals(point);
      if (!signals.any((v) => v != 0)) continue;
      final result = change > 0 ? 1 : -1;
      if (i >= trainEnd) {
        final confidence = botScore(point, weights);
        if (confidence.abs() < 0.00000001) continue;
        holdoutExamples++;
        if ((confidence > 0 ? 1 : -1) == result) holdoutCorrect++;
        if ((dayChange >= 0 ? 1 : -1) == result) baselineCorrect++;
      } else if (i + 1 < trainEnd) {
        trainingExamples++;
        active++;
        for (var k = 0; k < 3; k++) {
          grad[k] += signals[k] * result;
        }
      }
    }
    if (i < trainEnd && active > 0) {
      for (var k = 0; k < 3; k++) {
        weights[k] *= math.exp(0.12 * grad[k] / active);
        weights[k] = weights[k].clamp(0.05, 0.90).toDouble();
      }
      final total = weights.reduce((a, b) => a + b);
      for (var k = 0; k < 3; k++) {
        weights[k] /= total;
      }
    }
  }

  if (trainingExamples < 30 || holdoutExamples < 10) return null;
  return BotTrainingResult(
    weights: weights,
    trainingExamples: trainingExamples,
    holdoutExamples: holdoutExamples,
    holdoutCorrect: holdoutCorrect,
    baselineCorrect: baselineCorrect,
    coins: series.length,
  );
}
