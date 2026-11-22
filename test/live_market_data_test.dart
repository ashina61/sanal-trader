import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/services/live_market_data.dart';

void main() {
  MarketMiniTick tick(String symbol, double close, double open) => MarketMiniTick(
    symbol: symbol,
    close: close,
    open: open,
    time: DateTime.now().toUtc(),
  );

  test('Binance combined miniTicker parses a live quote', () {
    final raw = jsonEncode({
      'stream': 'btcusdt@miniTicker',
      'data': {
        's': 'BTCUSDT', 'c': '101', 'o': '100',
        'E': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
    });
    final parsed = MarketMiniTick.parse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.symbol, 'BTCUSDT');
    expect(parsed.close, 101);
  });

  test('Reject malformed and stale exchange ticks', () {
    expect(MarketMiniTick.parse('not json'), isNull);
    expect(MarketMiniTick.parse(jsonEncode({
      'data': {
        's': 'BTCUSDT', 'c': '100', 'o': '99',
        'E': DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      },
    })), isNull);
    expect(MarketMiniTick.parse(jsonEncode({
      'data': {
        's': 'BTCUSDT', 'c': '-12', 'o': '99',
        'E': DateTime.now().millisecondsSinceEpoch,
      },
    })), isNull);
  });

  test('Converts USDT spot + exchange USDT/TRY to real TRY paper quote', () {
    final converted = marketQuoteFromTicks(
      coin: tick('BTCUSDT', 100, 80),
      tryRate: tick('USDTTRY', 40, 38),
    );
    expect(converted, isNotNull);
    expect(converted!.priceTry, 4000);
    expect(converted.change24h, closeTo((4000 / 3040 - 1) * 100, 1e-9));
    expect(converted.symbol, 'BTC');
    expect(converted.isFresh, isTrue);
  });

  test('Historical chart is kept but last price is live', () {
    final prev = CoinQuote(
      id: 'bitcoin',
      symbol: 'BTC',
      name: 'Bitcoin',
      priceTry: 3000,
      change24h: 1,
      updatedAt: DateTime.now().toUtc(),
      sparkline: [2800, 2900, 3000],
    );
    final result = marketQuoteFromTicks(
      coin: tick('BTCUSDT', 100, 80),
      tryRate: tick('USDTTRY', 40, 38),
      previous: prev,
    )!;
    expect(result.sparkline, [2800, 2900, 4000]);
  });

  test('Unknown symbols never create fake tradable coins', () {
    expect(marketQuoteFromTicks(
      coin: tick('UNKNOWNUSDT', 100, 99),
      tryRate: tick('USDTTRY', 40, 39),
    ), isNull);
  });
}
