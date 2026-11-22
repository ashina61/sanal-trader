import 'dart:math' as math;

const double initialCashTry = 650;
const double tradingFeeRate = 0.001; // %0,1 - simülasyon varsayımı

class Holding {
  const Holding({required this.quantity, required this.costTry});

  final double quantity;
  final double costTry;

  Map<String, dynamic> toJson() => {
        'quantity': quantity,
        'costTry': costTry,
      };

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        costTry: (json['costTry'] as num?)?.toDouble() ?? 0,
      );
}

enum TradeSide { buy, sell }

class TradeRecord {
  const TradeRecord({
    required this.id,
    required this.coinId,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.priceTry,
    required this.grossTry,
    required this.feeTry,
    required this.cashChangeTry,
    required this.realizedPnlTry,
    required this.executedAt,
  });

  final String id;
  final String coinId;
  final String symbol;
  final TradeSide side;
  final double quantity;
  final double priceTry;
  final double grossTry;
  final double feeTry;
  final double cashChangeTry;
  final double realizedPnlTry;
  final DateTime executedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'coinId': coinId,
        'symbol': symbol,
        'side': side.name,
        'quantity': quantity,
        'priceTry': priceTry,
        'grossTry': grossTry,
        'feeTry': feeTry,
        'cashChangeTry': cashChangeTry,
        'realizedPnlTry': realizedPnlTry,
        'executedAt': executedAt.millisecondsSinceEpoch,
      };

  factory TradeRecord.fromJson(Map<String, dynamic> json) => TradeRecord(
        id: json['id'] as String,
        coinId: json['coinId'] as String,
        symbol: json['symbol'] as String,
        side: (json['side'] as String) == 'sell' ? TradeSide.sell : TradeSide.buy,
        quantity: (json['quantity'] as num).toDouble(),
        priceTry: (json['priceTry'] as num).toDouble(),
        grossTry: (json['grossTry'] as num).toDouble(),
        feeTry: (json['feeTry'] as num).toDouble(),
        cashChangeTry: (json['cashChangeTry'] as num).toDouble(),
        realizedPnlTry: (json['realizedPnlTry'] as num?)?.toDouble() ?? 0,
        executedAt: DateTime.fromMillisecondsSinceEpoch(json['executedAt'] as int),
      );
}

class Portfolio {
  const Portfolio({
    required this.cashTry,
    required this.holdings,
    required this.realizedPnlTry,
    required this.trades,
  });

  factory Portfolio.fresh() => const Portfolio(
        cashTry: initialCashTry,
        holdings: {},
        realizedPnlTry: 0,
        trades: [],
      );

  final double cashTry;
  final Map<String, Holding> holdings;
  final double realizedPnlTry;
  final List<TradeRecord> trades;

  double marketValue(Map<String, double> prices) {
    var total = cashTry;
    for (final holding in holdings.entries) {
      final price = prices[holding.key];
      if (price != null) total += holding.value.quantity * price;
    }
    return total;
  }

  double? fullMarketValue(Map<String, double> prices) {
    for (final entry in holdings.entries) {
      if (entry.value.quantity > 0 && !prices.containsKey(entry.key)) {
        return null;
      }
    }
    return marketValue(prices);
  }

  double get investedCostTry => holdings.values.fold(
        0, (sum, holding) => sum + holding.costTry);

  Map<String, dynamic> toJson() => {
        'cashTry': cashTry,
        'holdings': holdings.map((id, holding) => MapEntry(id, holding.toJson())),
        'realizedPnlTry': realizedPnlTry,
      };

  factory Portfolio.fromJson(
    Map<String, dynamic> json, {
    List<TradeRecord> trades = const [],
  }) {
    final holdings = <String, Holding>{};
    final rawHoldings = json['holdings'];
    if (rawHoldings is Map) {
      for (final entry in rawHoldings.entries) {
        if (entry.value is Map) {
          holdings[entry.key.toString()] = Holding.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    return Portfolio(
      cashTry: math.max(0.0, (json['cashTry'] as num?)?.toDouble() ?? initialCashTry),
      holdings: holdings,
      realizedPnlTry: (json['realizedPnlTry'] as num?)?.toDouble() ?? 0,
      trades: trades,
    );
  }

  Portfolio withTrades(List<TradeRecord> nextTrades) => Portfolio(
        cashTry: cashTry,
        holdings: holdings,
        realizedPnlTry: realizedPnlTry,
        trades: nextTrades,
      );
}
