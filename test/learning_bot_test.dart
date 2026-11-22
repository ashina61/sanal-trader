import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/learning_bot.dart';
import 'package:sanal_trader/services/trade_engine.dart';

CoinQuote quote({
  double price = 100,
  double change = 1.5,
  String id = 'bitcoin',
  String symbol = 'BTC',
  DateTime? time,
  bool history = true,
}) => CoinQuote(
  id: id,
  symbol: symbol,
  name: 'Example',
  priceTry: price,
  change24h: change,
  updatedAt: time ?? DateTime.now().toUtc(),
  sparkline: history ? List<double>.generate(168, (i) => 80 + i * 0.1) : [],
);

BotState enabled() => BotState.initial().copyWith(enabled: true);

void main() {
  test('Bot is OFF by default and requires explicit activation', () {
    final initial = BotState.initial();
    expect(initial.enabled, isFalse);
    expect(planBotOrder(state: initial, wallet: Portfolio.fresh(), quotes: {'bitcoin': quote()}), isNull);
  });

  test('Bullish signal spends <= 12% of virtual account', () {
    final q = quote();
    final order = planBotOrder(state: enabled(), wallet: Portfolio.fresh(), quotes: {'bitcoin': q});
    expect(order, isNotNull);
    expect(order!.side, TradeSide.buy);
    expect(order.amountTry, closeTo(78, 0.01));
    expect(order.amountTry, lessThanOrEqualTo(650));
  });

  test('Bot honors coin cooldown and does not duplicate buys', () {
    final q = quote();
    final initial = enabled();
    final first = planBotOrder(state: initial, wallet: Portfolio.fresh(), quotes: {q.id: q})!;
    final bought = executeVirtualTrade(
      current: Portfolio.fresh(), quote: q,
      side: TradeSide.buy, amountTry: first.amountTry,
    );
    final later = botRecordedTrade(initial, first);
    final another = planBotOrder(state: later, wallet: bought.portfolio, quotes: {q.id: q});
    expect(another, isNull);
  });

  test('Bot does not exceed daily transaction cap', () {
    final q = quote();
    final state = enabled().copyWith(
      day: DateTime.now().toUtc().toIso8601String().substring(0, 10),
      tradesToday: botMaxTradesPerDay,
    );
    expect(planBotOrder(state: state, wallet: Portfolio.fresh(), quotes: {q.id: q}), isNull);
  });

  test('Loss protection can sell virtual holdings even during cooldown', () {
    final firstQuote = quote();
    final bought = executeVirtualTrade(
      current: Portfolio.fresh(), quote: firstQuote,
      side: TradeSide.buy, amountTry: 78,
    );
    final initial = enabled();
    final first = BotOrder(quote: firstQuote, side: TradeSide.buy, amountTry: 78, reason: 'test', score: 0.7);
    final recent = botRecordedTrade(initial, first);
    final afterDrop = quote(price: 92, change: -4.0, history: false);
    final exit = planBotOrder(state: recent, wallet: bought.portfolio, quotes: {'bitcoin': afterDrop});
    expect(exit, isNotNull);
    expect(exit!.side, TradeSide.sell);
    expect(exit.reason, contains('Koruma'));
  });

  test('Old quote cannot generate a buy', () {
    final q = quote(time: DateTime.now().toUtc().subtract(const Duration(hours: 1)));
    expect(planBotOrder(state: enabled(), wallet: Portfolio.fresh(), quotes: {q.id: q}), isNull);
  });

  test('Outcome of a matured forecast updates expert weights', () {
    final now = DateTime.now().toUtc();
    final state = enabled().copyWith(predictions: {
      'bitcoin': BotPrediction(
        priceTry: 100, at: now.subtract(const Duration(minutes: 30)),
        signals: [1, 1, -1],
      ),
    });
    final updated = observeBot(state, [quote(price: 103, time: now)], now: now);
    expect(updated.evaluated, 1);
    expect(updated.correct, 1);
    expect(updated.weights[0], greaterThan(1 / 3));
    expect(updated.weights[2], lessThan(1 / 3));
    expect(updated.predictions['bitcoin']!.priceTry, 103);
  });

  test('No learning from quotes with unchanged provider timestamp', () {
    final now = DateTime.now().toUtc();
    final state = enabled().copyWith(predictions: {
      'bitcoin': BotPrediction(priceTry: 100, at: now, signals: [1, 1, -1]),
    });
    final result = observeBot(state, [quote(price: 105, time: now)], now: now);
    expect(result.evaluated, 0);
    expect(result.weights, state.weights);
  });

  test('Bot state preserves its learning data and default OFF failsafe', () {
    final state = enabled().copyWith(
      evaluated: 3, correct: 2,
      weights: [0.6, 0.3, 0.1],
    );
    final restored = BotState.fromJson(state.toJson());
    expect(restored.enabled, isTrue);
    expect(restored.evaluated, 3);
    expect(restored.correct, 2);
    expect(restored.weights[0], closeTo(0.6, 0.0001));
    expect(BotState.fromJson(const {'enabled': false}).enabled, isFalse);
  });
}
