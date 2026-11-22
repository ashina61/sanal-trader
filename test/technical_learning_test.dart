import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/services/learning_bot.dart';

CoinQuote snapshot(double price, DateTime at) => CoinQuote(
  id: 'bitcoin',
  symbol: 'BTC',
  name: 'Bitcoin',
  priceTry: price,
  change24h: 1,
  updatedAt: at,
  sparkline: List<double>.generate(168, (i) => 70 + i * .15),
);

void main() {
  test('Technical prediction is calibrated only after a later real snapshot', () {
    final now = DateTime.now().toUtc();
    final state = BotState.initial().copyWith(
      enabled: true,
      predictions: {
        'bitcoin': BotPrediction(
          priceTry: 100,
          at: now.subtract(const Duration(minutes: 30)),
          signals: const [1, 1, 0],
          technicalVote: 1,
        ),
      },
    );
    final updated = observeBot(state, [snapshot(104, now)], now: now);
    expect(updated.technicalEvaluated, 1);
    expect(updated.technicalCorrect, 1);
    expect(updated.technicalWeight, greaterThan(state.technicalWeight));
    expect(updated.technicalWeight, lessThan(.75));
    expect(BotState.fromJson(updated.toJson()).technicalEvaluated, 1);
  });

  test('Wrong technical direction reduces confidence gradually', () {
    final now = DateTime.now().toUtc();
    final state = BotState.initial().copyWith(
      enabled: true,
      predictions: {
        'bitcoin': BotPrediction(
          priceTry: 110,
          at: now.subtract(const Duration(minutes: 30)),
          signals: const [1, 0, 0],
          technicalVote: 1,
        ),
      },
    );
    final result = observeBot(state, [snapshot(100, now)], now: now);
    expect(result.technicalCorrect, 0);
    expect(result.technicalEvaluated, 1);
    expect(result.technicalWeight, lessThan(state.technicalWeight));
  });

  test('No technical calibration from the same timestamp or missing vote', () {
    final now = DateTime.now().toUtc();
    final state = BotState.initial().copyWith(
      enabled: true,
      predictions: {
        'bitcoin': BotPrediction(
          priceTry: 100, at: now,
          signals: const [1, 1, 0], technicalVote: 1,
        ),
      },
    );
    final result = observeBot(state, [snapshot(104, now)], now: now);
    expect(result.technicalEvaluated, 0);
    expect(result.technicalWeight, state.technicalWeight);
  });

  test('Legacy persisted bot can migrate without losing three strategy weights', () {
    final state = BotState.fromJson({
      'enabled': true,
      'weights': [0.2, 0.5, 0.3],
      'tradesToday': 2,
    });
    expect(state.weights.length, 3);
    expect(state.technicalWeight, .35);
    expect(state.technicalEvaluated, 0);
    expect(state.tradesToday, 2);
  });
}
