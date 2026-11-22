import '../models/coin_quote.dart';
import '../models/portfolio.dart';

class TradeException implements Exception {
  const TradeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TradeResult {
  const TradeResult({required this.portfolio, required this.trade});
  final Portfolio portfolio;
  final TradeRecord trade;
}

/// Tutar TL cinsindendir. Alışta tutar komisyon DAHİL nakit çıkışıdır.
/// Satışta tutar komisyon ÖNCESİ brüt satış tutarıdır.
TradeResult executeVirtualTrade({
  required Portfolio current,
  required CoinQuote quote,
  required TradeSide side,
  required double amountTry,
  DateTime? now,
  String? tradeId,
}) {
  if (!amountTry.isFinite || amountTry < 5) {
    throw const TradeException('En az ₺5 tutarında işlem gir.');
  }
  if (!quote.priceTry.isFinite || quote.priceTry <= 0) {
    throw const TradeException('Geçerli piyasa fiyatı bulunamadı.');
  }
  if (!quote.isFresh) {
    throw const TradeException('Fiyat güncel değil. Önce fiyatları yenile.');
  }

  final existing = current.holdings[quote.id] ??
      const Holding(quantity: 0, costTry: 0);
  final nextHoldings = Map<String, Holding>.from(current.holdings);
  final double gross;
  final double fee;
  final double qty;
  final double cashChange;
  final double realized;

  if (side == TradeSide.buy) {
    if (current.cashTry + 0.0000001 < amountTry) {
      throw const TradeException('Sanal TL bakiyen yetersiz.');
    }
    gross = amountTry / (1 + tradingFeeRate);
    fee = amountTry - gross;
    qty = gross / quote.priceTry;
    cashChange = -amountTry;
    realized = 0;
    nextHoldings[quote.id] = Holding(
      quantity: existing.quantity + qty,
      costTry: existing.costTry + amountTry,
    );
  } else {
    gross = amountTry;
    fee = gross * tradingFeeRate;
    qty = gross / quote.priceTry;
    if (qty > existing.quantity + 1e-12) {
      throw const TradeException('Satmak istediğin coin miktarı yetersiz.');
    }
    final sellQty = qty > existing.quantity ? existing.quantity : qty;
    final costRemoved = existing.quantity == 0
        ? 0.0
        : existing.costTry * (sellQty / existing.quantity);
    cashChange = gross - fee;
    realized = cashChange - costRemoved;
    final remaining = existing.quantity - sellQty;
    if (remaining < 1e-12) {
      nextHoldings.remove(quote.id);
    } else {
      nextHoldings[quote.id] = Holding(
        quantity: remaining,
        costTry: existing.costTry - costRemoved,
      );
    }
  }

  final timestamp = now ?? DateTime.now();
  final trade = TradeRecord(
    id: tradeId ?? '${timestamp.microsecondsSinceEpoch}_${side.name}',
    coinId: quote.id,
    symbol: quote.symbol,
    side: side,
    quantity: qty,
    priceTry: quote.priceTry,
    grossTry: gross,
    feeTry: fee,
    cashChangeTry: cashChange,
    realizedPnlTry: realized,
    executedAt: timestamp,
  );
  return TradeResult(
    trade: trade,
    portfolio: Portfolio(
      cashTry: current.cashTry + cashChange,
      holdings: nextHoldings,
      realizedPnlTry: current.realizedPnlTry + realized,
      trades: [trade, ...current.trades],
    ),
  );
}
