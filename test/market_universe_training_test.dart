import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/services/market_universe.dart';
import 'package:sanal_trader/services/bot_training.dart';

Map<String, dynamic> ticker(String pair, double volume) => {
  'symbol': pair, 'quoteVolume': volume.toString(),
  'lastPrice': '1.25', 'openPrice': '1.20',
};

CoinQuote trainingCoin(String id, {bool reverseHoldout = false}) {
  final points = List<double>.generate(168, (i) {
    final trend = 100 + 0.55 * i + ((i % 12) >= 7 ? -1.7 : 1.4);
    if (reverseHoldout && i >= 144) return 250 - (i - 144) * 0.8;
    return trend;
  });
  return CoinQuote(
    id: id, symbol: id.toUpperCase(), name: id,
    priceTry: points.last, change24h: 2,
    updatedAt: DateTime.now().toUtc(), sparkline: points,
    volume24hUsdt: 30000000,
  );
}

void main() {
  test('Market discovery ranks real liquidity instead of hardcoding only six', () {
    final feed = [
      ticker('BTCUSDT', 50000000), ticker('SOLUSDT', 40000000),
      ticker('ADAUSDT', 30000000), ticker('AVAXUSDT', 25000000),
      ticker('DOGEUSDT', 15000000),
      ticker('FAKEUSDT', 100),
    ];
    final picked = selectMarketUniverse(feed, limit: 5);
    expect(picked.pairs.length, 5);
    expect(picked.pairs['ADAUSDT'], 'ada');
    expect(picked.pairs['BTCUSDT'], 'bitcoin');
    expect(picked.volumes['AVAXUSDT'], 25000000);
    expect(picked.pairs.containsKey('FAKEUSDT'), isFalse);
  });

  test('Stable, synthetic, leveraged and non-USDT pairs are excluded', () {
    expect(eligibleUsdtSpotSymbol('USDCUSDT'), isFalse);
    expect(eligibleUsdtSpotSymbol('BTCUPUSDT'), isFalse);
    expect(eligibleUsdtSpotSymbol('ETHDOWNUSDT'), isFalse);
    expect(eligibleUsdtSpotSymbol('BTCTRY'), isFalse);
    expect(eligibleUsdtSpotSymbol('ADAUSDT'), isTrue);
  });

  test('Historical bot trains and measures truly withheld data', () {
    final coins = [trainingCoin('ada'), trainingCoin('eth'), trainingCoin('sol')];
    final result = trainHistoricalBot(coins);
    expect(result, isNotNull);
    expect(result!.coins, 3);
    expect(result.trainingExamples, greaterThan(30));
    expect(result.holdoutExamples, greaterThan(10));
    expect(result.holdoutAccuracy, inInclusiveRange(0, 1));
    expect(result.weights.reduce((a, b) => a + b), closeTo(1, 1e-8));
  });

  test('Changing only withheld future prices cannot affect trained weights', () {
    final first = [
      trainingCoin('ada'), trainingCoin('eth'), trainingCoin('sol'),
    ];
    final changed = [
      trainingCoin('ada', reverseHoldout: true),
      trainingCoin('eth', reverseHoldout: true),
      trainingCoin('sol', reverseHoldout: true),
    ];
    final a = trainHistoricalBot(first)!;
    final b = trainHistoricalBot(changed)!;
    for (var i = 0; i < 3; i++) {
      expect(a.weights[i], closeTo(b.weights[i], 1e-10));
    }
    expect(a.trainingExamples, b.trainingExamples);
  });

  test('Missing or incomplete price history is not treated as training', () {
    final result = trainHistoricalBot([
      trainingCoin('ada'),
      trainingCoin('eth'),
    ]);
    expect(result, isNull);
  });
}
