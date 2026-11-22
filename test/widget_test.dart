import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/main.dart';
import 'package:sanal_trader/models/coin_quote.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/portfolio_repository.dart';

// Widget constructor tests should not initialize platform plugins.
class _FakePortfolioRepository implements PortfolioRepository {
  @override
  Future<Portfolio> load() async => Portfolio.fresh();

  @override
  Future<Portfolio> placeOrder({
    required CoinQuote quote,
    required TradeSide side,
    required double amountTry,
  }) async => Portfolio.fresh();

  @override
  Future<void> reset() async {}
}

void main() {
  test('Uygulama yerel modda baslatilabilir', () {
    final app = TradingApp(
      repository: _FakePortfolioRepository(),
      cloudMode: false,
    );
    expect(app.cloudMode, isFalse);
    expect(app.repository, isA<PortfolioRepository>());
  });
}
