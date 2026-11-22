import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanal_trader/services/market_service_v2.dart';

Map<String, dynamic> coin(String id, String symbol, double volume) => {
  'id': id,
  'symbol': symbol,
  'name': id,
  'current_price': 100.0,
  'price_change_percentage_24h': 1.2,
  'total_volume': volume,
  'last_updated': DateTime.now().toUtc().toIso8601String(),
  'sparkline_in_7d': {
    'price': List<double>.generate(168, (i) => 90 + i * 0.1),
  },
};

void main() {
  test('Fallback scans more than six coins without inventing trade prices', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'data-api.binance.vision') {
        return http.Response('unavailable', 503);
      }
      if (request.url.host == 'api.coingecko.com') {
        return http.Response(jsonEncode([
          coin('bitcoin', 'btc', 100000000),
          coin('cardano', 'ada', 100000000),
          coin('avalanche', 'avax', 100000000),
          coin('chainlink', 'link', 100000000),
          coin('usd-coin', 'usdc', 100000000), // excluded stablecoin
          coin('thin', 'thin', 5), // excluded low volume
        ]), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('', 404);
    });
    final service = MarketService(client: client);
    final quotes = await service.fetchQuotes();
    expect(quotes.length, 4);
    expect(quotes.map((q) => q.symbol), containsAll(['BTC', 'ADA', 'AVAX', 'LINK']));
    expect(quotes.every((q) => q.isFresh && q.priceTry == 100), isTrue);
    expect(service.sourceStatus, contains('CoinGecko'));
    service.dispose();
  });
}
