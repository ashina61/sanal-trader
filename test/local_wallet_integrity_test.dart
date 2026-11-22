import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/bot_store.dart';
import 'package:sanal_trader/services/local_portfolio_repository.dart';

CoinQuote market() => CoinQuote(
  id: 'bitcoin', symbol: 'BTC', name: 'Bitcoin',
  priceTry: 100.0, change24h: 1.2,
  updatedAt: DateTime.now().toUtc(),
  sparkline: const [90, 95, 100],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // SharedPreferencesAsync does not use the legacy plugin mock.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('Fresh local bot requires explicit opt-in; never double-trades by default',
      () async {
    final store = BotStore();
    final initial = await store.load();
    expect(initial.enabled, isFalse);
  });

  test('Old local bot ON/OFF preference survives migration', () async {
    // Existing users keep their explicit preference and learning data.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
      'sanal_trader_learning_bot_v1':
          '{"enabled":false,"weights":[0.4,0.4,0.2],'
          '"predictions":{},"lastTrades":{},"day":"",'
          '"tradesToday":0,"evaluated":0,"correct":0,"activities":[]}',
    });
    final store = BotStore();
    final old = await store.load();
    expect(old.enabled, isFalse);
    expect(old.weights.first, closeTo(.4, .0001));
  });

  test('Concurrent local BUY requests do not overwrite each other',
      () async {
    final repo = LocalPortfolioRepository();
    final quote = market();
    await Future.wait([
      repo.placeOrder(
        quote: quote, side: TradeSide.buy, amountTry: 50),
      repo.placeOrder(
        quote: quote, side: TradeSide.buy, amountTry: 55),
    ]);
    final saved = await repo.load();
    expect(saved.cashTry, closeTo(545, .00001));
    expect(saved.trades.length, 2);
    expect(saved.holdings['bitcoin']!.costTry, closeTo(105, .00001));
  });

  test('Reset is serialized after an in-flight local order', () async {
    final repo = LocalPortfolioRepository();
    final buy = repo.placeOrder(
      quote: market(), side: TradeSide.buy, amountTry: 50,
    );
    final reset = repo.reset();
    await Future.wait([buy, reset]);
    final saved = await repo.load();
    expect(saved.cashTry, initialCashTry);
    expect(saved.trades, isEmpty);
    expect(saved.holdings, isEmpty);
  });
}
