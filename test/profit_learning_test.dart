import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/trade_engine.dart';
import 'package:sanal_trader/services/profit_learning.dart';
import 'package:sanal_trader/services/learning_bot.dart';
import 'package:sanal_trader/services/live_market_data.dart';
import 'package:sanal_trader/services/market_universe.dart';

CoinQuote q(double price, {String id = 'bitcoin'}) => CoinQuote(
  id: id, symbol: id == 'bitcoin' ? 'BTC' : 'ADA',
  name: id, priceTry: price, change24h: 0,
  updatedAt: DateTime.now().toUtc(),
  sparkline: List<double>.generate(168, (i) => price * (.9 + i / 1680)),
);

void main() {
  test('Actual virtual CLOSED trade P/L includes buy and sell fees', () {
    final state = BotState.initial().copyWith(enabled: true);
    final b = executeVirtualTrade(
      current: Portfolio.fresh(), quote: q(100),
      side: TradeSide.buy, amountTry: 70,
    );
    final buyOrder = BotOrder(
      quote: q(100), side: TradeSide.buy, amountTry: 70,
      reason: 'test', score: .7,
    );
    final afterBuy = botRecordedTrade(
      state, buyOrder, executedTrade: b.trade);
    expect(afterBuy.profitLearning.closedTrades, 0);
    expect(afterBuy.profitLearning.realizedTry, 0);
    expect(afterBuy.profitLearning.totalBotFeesTry, greaterThan(0));

    final sellGross = b.portfolio.holdings['bitcoin']!.quantity * 110;
    final sale = executeVirtualTrade(
      current: b.portfolio, quote: q(110),
      side: TradeSide.sell, amountTry: sellGross,
    );
    final sellOrder = BotOrder(
      quote: q(110), side: TradeSide.sell, amountTry: sellGross,
      reason: 'test', score: -1.0,
    );
    final afterSell = botRecordedTrade(
      afterBuy, sellOrder, executedTrade: sale.trade,
    );
    expect(afterSell.profitLearning.closedTrades, 1);
    expect(afterSell.profitLearning.winningTrades, 1);
    expect(afterSell.profitLearning.realizedTry,
      closeTo(sale.trade.realizedPnlTry, 1e-8));
    expect(afterSell.profitLearning.realizedTry, greaterThan(0));
    expect(afterSell.profitLearning.edge('bitcoin'), 0); // no overfitting to one win
    final restored = BotState.fromJson(jsonDecode(jsonEncode(afterSell.toJson())));
    expect(restored.profitLearning.realizedTry,
      closeTo(afterSell.profitLearning.realizedTry, 1e-8));
  });

  test('Bot does not learn from an unexecuted or mismatched order', () {
    final state = BotState.initial().copyWith(enabled: true);
    final buyOrder = BotOrder(
      quote: q(100), side: TradeSide.buy, amountTry: 50,
      reason: 'test', score: .5,
    );
    final noExecution = botRecordedTrade(state, buyOrder);
    expect(noExecution.profitLearning.closedTrades, 0);
    expect(noExecution.profitLearning.totalBotFeesTry, 0);

    final transaction = executeVirtualTrade(
      current: Portfolio.fresh(), quote: q(100),
      side: TradeSide.buy, amountTry: 50,
    ).trade;
    final mismatch = BotOrder(
      quote: q(100, id: 'cardano'), side: TradeSide.buy,
      amountTry: 50, reason: 'test', score: .5,
    );
    expect(botRecordedTrade(state, mismatch,
      executedTrade: transaction).profitLearning.totalBotFeesTry, 0);
  });

  test('A losing virtual exit is actually reflected in learned results', () {
    final bought = executeVirtualTrade(
      current: Portfolio.fresh(), quote: q(100),
      side: TradeSide.buy, amountTry: 50,
    );
    final sold = executeVirtualTrade(
      current: bought.portfolio, quote: q(80),
      side: TradeSide.sell,
      amountTry: bought.portfolio.holdings['bitcoin']!.quantity * 80,
    );
    final ledger = const ProfitLearning.empty().record(sold.trade);
    expect(ledger.realizedTry, lessThan(0));
    expect(ledger.closedTrades, 1);
    expect(ledger.winningTrades, 0);
    expect(ledger.winRate, 0);
    expect(ledger.edge('bitcoin'), 0);
  });

  test('Coin profitability edge is bounded after repeat exits', () {
    var ledger = const ProfitLearning.empty();
    for (var i = 0; i < 10; i++) {
      final b = executeVirtualTrade(
        current: Portfolio.fresh(), quote: q(100),
        side: TradeSide.buy, amountTry: 60,
      );
      final sell = executeVirtualTrade(
        current: b.portfolio, quote: q(130),
        side: TradeSide.sell,
        amountTry: b.portfolio.holdings['bitcoin']!.quantity * 130,
      );
      ledger = ledger.record(sell.trade);
    }
    expect(ledger.edge('bitcoin'), greaterThan(0));
    expect(ledger.edge('bitcoin'), lessThanOrEqualTo(.20));
    expect(ProfitLearning.fromJson(ledger.toJson()).closedTrades, 10);
  });

  test('Full-market websocket parser validates batch events', () {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final payload = jsonEncode([
      {'s': 'BTCUSDT', 'c': '101', 'o': '99', 'E': now},
      {'s': 'ADAUSDT', 'c': '0.4', 'o': '0.5', 'E': now},
      {'s': 'BADUSDT', 'c': '-5', 'o': '9', 'E': now},
    ]);
    final ticks = MarketMiniTick.parseBatch(payload);
    expect(ticks.length, 2);
    expect(ticks.map((t) => t.symbol), ['BTCUSDT', 'ADAUSDT']);
    expect(MarketMiniTick.parseBatch(
      jsonEncode({'stream': '!miniTicker@arr',
        'data': [{'s': 'SOLUSDT','c':'10','o':'9','E':now}]})).length, 1);
  });

  test('Coin discovery can scan more than old 72-token ceiling', () {
    final raw = List.generate(160, (i) => {
      'symbol': 'COIN${i}USDT',
      'quoteVolume': '5000000',
      'lastPrice': '0.1',
    });
    final result = selectMarketUniverse(raw);
    expect(result.pairs.length, 160);
    expect(result.pairs.keys, contains('COIN150USDT'));
  });
}
