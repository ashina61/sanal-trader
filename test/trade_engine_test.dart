import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/trade_engine.dart';

CoinQuote liveQuote({double price = 100}) => CoinQuote(
  id: 'bitcoin', symbol: 'BTC', name: 'Bitcoin',
  priceTry: price, change24h: 1,
  updatedAt: DateTime.now().toUtc(), sparkline: const [99, 100],
);

void main() {
  test('₺100 alışta komisyon dahil nakit ₺550 olur', () {
    final result = executeVirtualTrade(
      current: Portfolio.fresh(), quote: liveQuote(),
      side: TradeSide.buy, amountTry: 100,
    );
    expect(result.portfolio.cashTry, closeTo(550, 0.00001));
    expect(result.portfolio.holdings['bitcoin']!.quantity, closeTo(100 / 1.001 / 100, 0.000001));
    expect(result.trade.feeTry, greaterThan(0));
  });

  test('Yetersiz bakiye reddedilir', () {
    expect(() => executeVirtualTrade(
      current: Portfolio.fresh(), quote: liveQuote(),
      side: TradeSide.buy, amountTry: 700,
    ), throwsA(isA<TradeException>()));
  });

  test('Coin olmadan satış reddedilir', () {
    expect(() => executeVirtualTrade(
      current: Portfolio.fresh(), quote: liveQuote(),
      side: TradeSide.sell, amountTry: 100,
    ), throwsA(isA<TradeException>()));
  });

  test('Alış ve satış toplam nakitte komisyon düşer', () {
    final quote = liveQuote();
    final bought = executeVirtualTrade(
      current: Portfolio.fresh(), quote: quote,
      side: TradeSide.buy, amountTry: 100,
    );
    final sold = executeVirtualTrade(
      current: bought.portfolio, quote: quote,
      side: TradeSide.sell, amountTry: 100 / 1.001,
    );
    expect(sold.portfolio.cashTry, lessThan(650));
    expect(sold.portfolio.cashTry, greaterThan(649));
    expect(sold.portfolio.holdings, isEmpty);
    expect(sold.portfolio.trades.length, 2);
    expect(sold.portfolio.realizedPnlTry, lessThan(0));
  });

  test('Eski fiyatla işlem yapılamaz', () {
    final stale = CoinQuote(
      id: 'bitcoin', symbol: 'BTC', name: 'Bitcoin',
      priceTry: 100, change24h: 0,
      updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      sparkline: const [],
    );
    expect(() => executeVirtualTrade(
      current: Portfolio.fresh(), quote: stale,
      side: TradeSide.buy, amountTry: 50,
    ), throwsA(isA<TradeException>()));
  });
}
