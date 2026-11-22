import 'dart:math' as math;
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import 'technical_analysis.dart';

/// Online expert-weighting strategy for paper trading ONLY.
/// Predictions are evaluated using later market snapshots, never future data.
/// This is an adaptive statistical strategy, not an LLM or profit guarantee.
const botObservationPeriod = Duration(minutes: 15);
const botTradeCooldown = Duration(minutes: 30);
const botMaxTradesPerDay = 8;
const botMaxOrderShare = 0.12;
const botCashReserveShare = 0.30;
const botMaxCoinShare = 0.25;
const botMaxTotalExposureShare = 0.65;
const botMinimumOrderTry = 5.0;
const botStopLossFraction = 0.06;
const botTakeProfitFraction = 0.08;
const botBuyThreshold = 0.45;
const botSellThreshold = -0.45;

const botExpertLabels = ['Kısa trend', '24s momentum', 'Ters yön'];

class BotPrediction {
  const BotPrediction({required this.priceTry, required this.at, required this.signals});
  final double priceTry;
  final DateTime at;
  final List<int> signals;

  Map<String, dynamic> toJson() => {
    'priceTry': priceTry,
    'at': at.toUtc().millisecondsSinceEpoch,
    'signals': signals,
  };

  factory BotPrediction.fromJson(Map<String, dynamic> json) {
    final rawSignals = json['signals'];
    final signals = rawSignals is List ? rawSignals.whereType<num>().map((s) => s.toInt().clamp(-1, 1)).toList() : <int>[];
    return BotPrediction(
      priceTry: (json['priceTry'] as num?)?.toDouble() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0, isUtc: true),
      signals: signals.length == 3 ? signals : [0, 0, 0],
    );
  }
}

class BotActivity {
  const BotActivity({required this.at, required this.message});
  final DateTime at;
  final String message;
  Map<String, dynamic> toJson() => {'at': at.toUtc().millisecondsSinceEpoch, 'message': message};

  factory BotActivity.fromJson(Map<String, dynamic> json) => BotActivity(
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0, isUtc: true),
    message: (json['message'] as String?) ?? '',
  );
}

class BotState {
  const BotState({
    required this.enabled,
    required this.weights,
    required this.predictions,
    required this.lastTrades,
    required this.day,
    required this.tradesToday,
    required this.evaluated,
    required this.correct,
    required this.activities,
    this.trainingVersion = 0,
    this.trainingExamples = 0,
    this.holdoutExamples = 0,
    this.holdoutCorrect = 0,
    this.baselineCorrect = 0,
    this.trainedCoins = 0,
    this.peakEquityTry = initialCashTry,
  });

  factory BotState.initial() => const BotState(
    enabled: false, weights: [1 / 3, 1 / 3, 1 / 3],
    predictions: {}, lastTrades: {}, day: '', tradesToday: 0,
    evaluated: 0, correct: 0, activities: [],
  );

  final bool enabled;
  final List<double> weights;
  final Map<String, BotPrediction> predictions;
  final Map<String, DateTime> lastTrades;
  final String day;
  final int tradesToday;
  final int evaluated;
  final int correct;
  final List<BotActivity> activities;
  final int trainingVersion;
  final int trainingExamples;
  final int holdoutExamples;
  final int holdoutCorrect;
  final int baselineCorrect;
  final int trainedCoins;
  final double peakEquityTry;

  BotState copyWith({
    bool? enabled,
    List<double>? weights,
    Map<String, BotPrediction>? predictions,
    Map<String, DateTime>? lastTrades,
    String? day,
    int? tradesToday,
    int? evaluated,
    int? correct,
    List<BotActivity>? activities,
    int? trainingVersion,
    int? trainingExamples,
    int? holdoutExamples,
    int? holdoutCorrect,
    int? baselineCorrect,
    int? trainedCoins,
    double? peakEquityTry,
  }) => BotState(
    enabled: enabled ?? this.enabled,
    weights: weights ?? this.weights,
    predictions: predictions ?? this.predictions,
    lastTrades: lastTrades ?? this.lastTrades,
    day: day ?? this.day,
    tradesToday: tradesToday ?? this.tradesToday,
    evaluated: evaluated ?? this.evaluated,
    correct: correct ?? this.correct,
    activities: activities ?? this.activities,
    trainingVersion: trainingVersion ?? this.trainingVersion,
    trainingExamples: trainingExamples ?? this.trainingExamples,
    holdoutExamples: holdoutExamples ?? this.holdoutExamples,
    holdoutCorrect: holdoutCorrect ?? this.holdoutCorrect,
    baselineCorrect: baselineCorrect ?? this.baselineCorrect,
    trainedCoins: trainedCoins ?? this.trainedCoins,
    peakEquityTry: peakEquityTry ?? this.peakEquityTry,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'weights': weights,
    'predictions': predictions.map((id, p) => MapEntry(id, p.toJson())),
    'lastTrades': lastTrades.map((id, date) => MapEntry(id, date.toUtc().millisecondsSinceEpoch)),
    'day': day,
    'tradesToday': tradesToday,
    'evaluated': evaluated,
    'correct': correct,
    'activities': activities.map((a) => a.toJson()).toList(),
    'trainingVersion': trainingVersion,
    'trainingExamples': trainingExamples,
    'holdoutExamples': holdoutExamples,
    'holdoutCorrect': holdoutCorrect,
    'baselineCorrect': baselineCorrect,
    'trainedCoins': trainedCoins,
    'peakEquityTry': peakEquityTry,
  };

  factory BotState.fromJson(Map<String, dynamic> json) {
    final raw = json['weights'];
    final candidates = raw is List ? raw.whereType<num>().map((n) => n.toDouble()).toList() : <double>[];
    final valid = candidates.length == 3 && candidates.every((w) => w.isFinite && w > 0);
    final sum = valid ? candidates.reduce((a, b) => a + b) : 1.0;
    final weights = valid && sum > 0 ? candidates.map((w) => w / sum).toList() : <double>[1 / 3, 1 / 3, 1 / 3];
    final preds = <String, BotPrediction>{};
    if (json['predictions'] is Map) {
      for (final e in (json['predictions'] as Map).entries) {
        if (e.value is Map) preds[e.key.toString()] = BotPrediction.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    }
    final times = <String, DateTime>{};
    if (json['lastTrades'] is Map) {
      for (final e in (json['lastTrades'] as Map).entries) {
        if (e.value is num) times[e.key.toString()] = DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt(), isUtc: true);
      }
    }
    final activities = (json['activities'] is List ? json['activities'] as List : const [])
        .whereType<Map>().map((e) => BotActivity.fromJson(Map<String, dynamic>.from(e))).take(20).toList();
    return BotState(
      enabled: json['enabled'] == true,
      weights: weights, predictions: preds, lastTrades: times,
      day: (json['day'] as String?) ?? '',
      tradesToday: math.max(0, (json['tradesToday'] as num?)?.toInt() ?? 0),
      evaluated: math.max(0, (json['evaluated'] as num?)?.toInt() ?? 0),
      correct: math.max(0, (json['correct'] as num?)?.toInt() ?? 0),
      activities: activities,
      trainingVersion: (json['trainingVersion'] as num?)?.toInt() ?? 0,
      trainingExamples: (json['trainingExamples'] as num?)?.toInt() ?? 0,
      holdoutExamples: (json['holdoutExamples'] as num?)?.toInt() ?? 0,
      holdoutCorrect: (json['holdoutCorrect'] as num?)?.toInt() ?? 0,
      baselineCorrect: (json['baselineCorrect'] as num?)?.toInt() ?? 0,
      trainedCoins: (json['trainedCoins'] as num?)?.toInt() ?? 0,
      peakEquityTry: math.max(initialCashTry,
        (json['peakEquityTry'] as num?)?.toDouble() ?? initialCashTry),
    );
  }

  int tradesFor(DateTime now) => day == _utcDay(now) ? tradesToday : 0;
}

String _utcDay(DateTime date) => date.toUtc().toIso8601String().substring(0, 10);

/// Signals are computed only from already-observed historical points.
List<int> botSignals(CoinQuote quote) {
  final points = quote.sparkline;
  if (points.length < 26 || !quote.priceTry.isFinite || quote.priceTry <= 0) return [0, 0, 0];
  final p6 = points[points.length - 7];
  if (!p6.isFinite || p6 <= 0) return [0, 0, 0];
  final shortChange = (quote.priceTry / p6 - 1) * 100;
  final daily = quote.change24h;
  int threshold(double v, double min) => v > min ? 1 : (v < -min ? -1 : 0);
  return [
    threshold(shortChange, 0.5),
    threshold(daily, 1.0),
    -threshold(daily, 2.0),
  ];
}

double botScore(CoinQuote q, List<double> weights) {
  final s = botSignals(q);
  return s[0] * weights[0] + s[1] * weights[1] + s[2] * weights[2];
}

/// Learn only if at least 15 minutes of newer *provider timestamps* have passed.
BotState observeBot(BotState state, Iterable<CoinQuote> quotes, {DateTime? now}) {
  if (!state.enabled) return state;
  final currentTime = (now ?? DateTime.now()).toUtc();
  final weights = List<double>.from(state.weights);
  final preds = Map<String, BotPrediction>.from(state.predictions);
  var evaluated = state.evaluated;
  var correct = state.correct;

  for (final quote in quotes) {
    if (!quote.isFresh || quote.updatedAt.toUtc().isAfter(currentTime)) continue;
    final previous = preds[quote.id];
    if (previous != null) {
      final elapsed = quote.updatedAt.toUtc().difference(previous.at);
      if (elapsed < botObservationPeriod) continue;
      if (previous.priceTry.isFinite && previous.priceTry > 0 && quote.priceTry.isFinite) {
        final move = quote.priceTry / previous.priceTry - 1;
        if (move.abs() >= 0.001) {
          final outcome = move > 0 ? 1 : -1;
          final vote = List<double>.generate(3, (i) => weights[i] * previous.signals[i])
              .reduce((a, b) => a + b);
          if (vote.abs() > 0.000001) {
            evaluated++;
            if ((vote > 0 ? 1 : -1) == outcome) correct++;
          }
          for (var i = 0; i < 3; i++) {
            weights[i] *= math.exp(0.16 * previous.signals[i] * outcome);
          }
          final weightSum = weights.reduce((a, b) => a + b);
          for (var i = 0; i < 3; i++) {
            weights[i] = (weights[i] / weightSum).clamp(0.05, 0.90).toDouble();
          }
          final normalized = weights.reduce((a, b) => a + b);
          for (var i = 0; i < 3; i++) {
            weights[i] /= normalized;
          }
        }
      }
    }
    final signals = botSignals(quote);
    if (signals.any((value) => value != 0)) {
      preds[quote.id] = BotPrediction(priceTry: quote.priceTry, at: quote.updatedAt.toUtc(), signals: signals);
    } else {
      preds.remove(quote.id);
    }
  }
  return state.copyWith(weights: weights, predictions: preds, evaluated: evaluated, correct: correct);
}

class BotOrder {
  const BotOrder({required this.quote, required this.side, required this.amountTry, required this.reason, required this.score});
  final CoinQuote quote;
  final TradeSide side;
  final double amountTry;
  final String reason;
  final double score;
}

BotOrder? planBotOrder({
  required BotState state,
  required Portfolio wallet,
  required Map<String, CoinQuote> quotes,
  DateTime? now,
}) {
  if (!state.enabled || state.tradesFor(now ?? DateTime.now()) >= botMaxTradesPerDay) return null;
  final time = (now ?? DateTime.now()).toUtc();
  final available = quotes.values.where((q) => q.isFresh && q.priceTry > 0 && q.priceTry.isFinite).toList();
  final benchmark = quotes['bitcoin'];
  final btc = benchmark == null ? TechnicalReport.insufficient : analyzeTechnical(benchmark);
  if (available.isEmpty) return null;
  bool cooled(CoinQuote q) {
    final last = state.lastTrades[q.id];
    return last == null || time.difference(last) >= botTradeCooldown;
  }

  // Sell existing positions first; risk exits precede signal-driven trades.
  final candidates = <BotOrder>[];
  for (final q in available) {
    final held = wallet.holdings[q.id];
    final gross = (held?.quantity ?? 0) * q.priceTry;
    if (held == null || gross < botMinimumOrderTry || held.quantity <= 0) continue;
    final avg = held.costTry / held.quantity;
    final change = q.priceTry / avg - 1;
    final score = botScore(q, state.weights);
    if (change <= -botStopLossFraction) {
      candidates.add(BotOrder(quote: q, side: TradeSide.sell, amountTry: gross, reason: 'Koruma: maliyetin %6 altında', score: -2.0));
    } else if (change >= botTakeProfitFraction) {
      candidates.add(BotOrder(quote: q, side: TradeSide.sell, amountTry: gross, reason: 'Hedef: maliyetin %8 üstünde', score: -1.8));
    } else if (cooled(q) && (score <= botSellThreshold ||
        (analyzeTechnical(q).ready && analyzeTechnical(q).score <= -0.40))) {
      candidates.add(BotOrder(
        quote: q, side: TradeSide.sell, amountTry: gross,
        reason: 'Negatif momentum / teknik satış baskısı',
        score: score,
      ));
    }
  }
  if (candidates.isNotEmpty) {
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.first;
  }

  if (wallet.fullMarketValue(quotes.map((id, q) => MapEntry(id, q.priceTry))) == null) return null;
  final equity = wallet.marketValue(quotes.map((id, q) => MapEntry(id, q.priceTry)));
  if (!equity.isFinite || equity < botMinimumOrderTry) return null;
  final exposure = equity - wallet.cashTry;
  // A 12% portfolio drawdown suspends new buys but still allows exits.
  if (equity < state.peakEquityTry * 0.88) return null;
  for (final q in available) {
    if (!cooled(q) || !botSignals(q).any((signal) => signal != 0)) continue;
    final score = botScore(q, state.weights);
    if (score < botBuyThreshold) continue;
    final report = analyzeTechnical(q);
    // Do not invent technical confirmation: close history is required.
    if (!report.ready || report.score < .18 ||
        report.trend == TrendDirection.falling) continue;
    // Crypto-market regime: suppress altcoin buys in a falling BTC market.
    if (q.id != 'bitcoin' && btc.ready &&
        btc.trend == TrendDirection.falling && btc.score < -.20) continue;
    if (report.volatility24hPct > 18 || report.atrPct > 9) continue;
    final positionValue = (wallet.holdings[q.id]?.quantity ?? 0) * q.priceTry;
    final maxBuy = [
      wallet.cashTry,
      equity * botMaxOrderShare,
      wallet.cashTry - equity * botCashReserveShare,
      equity * botMaxCoinShare - positionValue,
      equity * botMaxTotalExposureShare - exposure,
    ].reduce(math.min);
    // No claim of a guaranteed stop; smaller exposure when returns are noisy.
    final volFactor = report.volatility24hPct > 9 ? .4
        : report.volatility24hPct > 6 ? .65 : 1.0;
    final amount = (maxBuy * volFactor * 100).floorToDouble() / 100;
    if (amount >= botMinimumOrderTry) {
      candidates.add(BotOrder(
        quote: q, side: TradeSide.buy, amountTry: amount,
        reason: 'Trend ${report.trendLabel}, RSI ${report.rsi.toStringAsFixed(0)}, '
            'MACD ${report.macdHistogram >= 0 ? '+' : '-'}, '
            'teknik ${report.score.toStringAsFixed(2)}, '
            'öğrenen puan ${score.toStringAsFixed(2)}',
        score: score + report.score * .5,
      ));
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.isEmpty ? null : candidates.first;
}

BotState botRecordedTrade(BotState state, BotOrder order, {DateTime? now}) {
  final time = (now ?? DateTime.now()).toUtc();
  final latest = Map<String, DateTime>.from(state.lastTrades)..[order.quote.id] = time;
  final daily = state.tradesFor(time);
  final action = order.side == TradeSide.buy ? 'AL' : 'SAT';
  final text = action + ' ' + order.quote.symbol + ' • ' + order.amountTry.toStringAsFixed(2) +
      ' TL • ' + order.reason + ' • Sinyal ' + order.score.toStringAsFixed(2);
  return state.copyWith(
    day: _utcDay(time),
    tradesToday: daily + 1,
    lastTrades: latest,
    activities: [BotActivity(at: time, message: text), ...state.activities].take(20).toList(),
  );
}
