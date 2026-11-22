import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/backtest_summary.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/services/bot_training.dart';
import 'package:sanal_trader/services/walk_forward_backtest.dart';
import 'package:sanal_trader/services/learning_bot.dart';

CoinQuote sample(String id, {bool flat = false, bool reverse = false}) {
  final points = List<double>.generate(168, (i) {
    if (flat) return 100;
    final trend = 100 + i * .7;
    if (reverse && i >= 144) return 100 + 144 * .7 - (i - 144) * 1.5;
    return trend;
  });
  return CoinQuote(
    id: id, symbol: id.toUpperCase(), name: id,
    priceTry: points.last, change24h: 3,
    updatedAt: DateTime.now().toUtc(), sparkline: points,
  );
}

void main() {
  test('Insufficient source series never produce invented backtest trades', () {
    expect(walkForwardBacktest([sample('a'), sample('b')],
      weights: [.5,.4,.1]), isNull);
  });

  test('Flat prices imply negative fee-adjusted buy-and-hold versus cash', () {
    final result = walkForwardBacktest(
      [sample('a',flat:true),sample('b',flat:true),sample('c',flat:true)],
      weights: [.5,.4,.1],
    )!;
    expect(result.coins, 3);
    expect(result.closedTrades, 0);
    expect(result.strategyReturnPct, closeTo(0, .0000001));
    expect(result.buyHoldReturnPct, lessThan(0));
    expect(result.maxDrawdownPct, closeTo(0, .0000001));
    expect(result.winRate, isNull);
  });

  test('The model records different results when unseen holdout market reverses', () {
    final bull = [
      sample('a'),sample('b'),sample('c'),
    ];
    final bear = [
      sample('a',reverse:true),sample('b',reverse:true),
      sample('c',reverse:true),
    ];
    const weights = <double>[.5,.4,.1];
    final forward = walkForwardBacktest(bull,weights: weights)!;
    final reversal = walkForwardBacktest(bear,weights: weights)!;
    expect(forward.coins, 3);
    expect(reversal.coins, 3);
    expect(forward.buyHoldReturnPct, greaterThan(reversal.buyHoldReturnPct));
    expect(forward.strategyReturnPct.isFinite, isTrue);
    expect(reversal.strategyReturnPct.isFinite, isTrue);
    // If a trade is executed on historical closes it must be fee accounted.
    expect(forward.maxDrawdownPct, inInclusiveRange(0, 100));
  });

  test('Future holdout cannot alter weights trained only on earlier data', () {
    final a=[sample('a'),sample('b'),sample('c')];
    final b=[sample('a',reverse:true),sample('b',reverse:true),
      sample('c',reverse:true)];
    final x=trainHistoricalBot(a);
    final y=trainHistoricalBot(b);
    expect(x, isNotNull);
    expect(y, isNotNull);
    for(var i=0;i<3;i++) {
      expect(x!.weights[i], closeTo(y!.weights[i], 1e-9));
    }
  });

  test('Backtest JSON roundtrip persists only its separate hypothetical results', () {
    final result = walkForwardBacktest(
      [sample('a'),sample('b'),sample('c')],weights: [.5,.4,.1])!;
    final decoded = BacktestSummary.fromJson(result.toJson());
    expect(decoded.coins, 3);
    expect(decoded.strategyReturnPct, result.strategyReturnPct);
    final state=BotState.initial().copyWith(backtest: result);
    final restored=BotState.fromJson(state.toJson());
    expect(restored.backtest, isNotNull);
    expect(restored.backtest!.coins, 3);
    expect(restored.profitLearning.closedTrades, 0);
  });
}
