import '../models/coin_quote.dart';
import '../models/portfolio.dart';

abstract class PortfolioRepository {
  Future<Portfolio> load();

  Future<Portfolio> placeOrder({
    required CoinQuote quote,
    required TradeSide side,
    required double amountTry,
  });

  Future<void> reset();
}
