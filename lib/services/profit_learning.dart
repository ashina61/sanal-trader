import 'dart:math' as math;
import '../models/portfolio.dart';

/// Performance from EXECUTED virtual BOT orders only. Never labels a forecast
/// as a successful trade, and never reads future prices.
class CoinOutcome {
  const CoinOutcome({
    required this.closed,
    required this.wins,
    required this.realizedTry,
    required this.meanRoi,
  });

  const CoinOutcome.empty()
      : closed = 0, wins = 0, realizedTry = 0, meanRoi = 0;

  final int closed;
  final int wins;
  final double realizedTry;
  final double meanRoi;

  double get winRate => closed == 0 ? 0 : wins / closed;

  Map<String, dynamic> toJson() => {
    'closed': closed, 'wins': wins,
    'realizedTry': realizedTry, 'meanRoi': meanRoi,
  };

  factory CoinOutcome.fromJson(Map<String, dynamic> json) {
    double finite(dynamic n) {
      final v = (n as num?)?.toDouble() ?? 0;
      return v.isFinite ? v : 0;
    }
    return CoinOutcome(
      closed: math.max(0, (json['closed'] as num?)?.toInt() ?? 0),
      wins: math.max(0, (json['wins'] as num?)?.toInt() ?? 0),
      realizedTry: finite(json['realizedTry']),
      meanRoi: finite(json['meanRoi']).clamp(-0.5, 0.5).toDouble(),
    );
  }
}

class ProfitLearning {
  const ProfitLearning({
    required this.perCoin,
    required this.closedTrades,
    required this.winningTrades,
    required this.realizedTry,
    required this.totalBotFeesTry,
    required this.grossWinTry,
    required this.grossLossTry,
  });

  const ProfitLearning.empty()
      : perCoin = const {},
        closedTrades = 0,
        winningTrades = 0,
        realizedTry = 0,
        totalBotFeesTry = 0,
        grossWinTry = 0,
        grossLossTry = 0;

  final Map<String, CoinOutcome> perCoin;
  final int closedTrades;
  final int winningTrades;
  /// Net realized P/L already accounts for virtual BUY and SELL fees.
  final double realizedTry;
  /// Informational only: never subtract these fees again from realizedTry.
  final double totalBotFeesTry;
  final double grossWinTry;
  final double grossLossTry;

  double? get winRate =>
      closedTrades == 0 ? null : winningTrades / closedTrades;

  double? get profitFactor =>
      grossLossTry <= 0 ? null : grossWinTry / grossLossTry;

  /// Conservative influence on candidate ranking, not a promise of return.
  /// Two completed profitable/loss-making exits are required before any bias.
  double edge(String coinId) {
    final c = perCoin[coinId];
    if (c == null || c.closed < 2) return 0;
    final confidence = math.min(1.0, c.closed / 8.0);
    final historyBias = (c.meanRoi * 2.0).clamp(-.20, .20).toDouble();
    return historyBias * confidence;
  }

  ProfitLearning record(TradeRecord trade) {
    final updatedFees = totalBotFeesTry + trade.feeTry;
    if (trade.side != TradeSide.sell) {
      return ProfitLearning(
        perCoin: perCoin, closedTrades: closedTrades,
        winningTrades: winningTrades, realizedTry: realizedTry,
        totalBotFeesTry: updatedFees, grossWinTry: grossWinTry,
        grossLossTry: grossLossTry,
      );
    }
    // Virtual realizedPnlTry = cash received - allocated cost incl. buy fee.
    final costRemoved =
        trade.grossTry - trade.feeTry - trade.realizedPnlTry;
    if (!costRemoved.isFinite || costRemoved <= 0 ||
        !trade.realizedPnlTry.isFinite) {
      return this; // Corrupt trade: never use in learning.
    }
    final previous = perCoin[trade.coinId] ?? const CoinOutcome.empty();
    final roi = (trade.realizedPnlTry / costRemoved)
        .clamp(-0.5, 0.5).toDouble();
    final next = CoinOutcome(
      closed: previous.closed + 1,
      wins: previous.wins + (trade.realizedPnlTry > 0 ? 1 : 0),
      realizedTry: previous.realizedTry + trade.realizedPnlTry,
      // EWMA adapts to a changing market without allowing one outlier
      // to dominate future position selection.
      meanRoi: previous.closed == 0
          ? roi : .8 * previous.meanRoi + .2 * roi,
    );
    return ProfitLearning(
      perCoin: {...perCoin, trade.coinId: next},
      closedTrades: closedTrades + 1,
      winningTrades: winningTrades + (trade.realizedPnlTry > 0 ? 1 : 0),
      realizedTry: realizedTry + trade.realizedPnlTry,
      totalBotFeesTry: updatedFees,
      grossWinTry: grossWinTry + math.max(0, trade.realizedPnlTry),
      grossLossTry: grossLossTry + math.max(0, -trade.realizedPnlTry),
    );
  }

  Map<String, dynamic> toJson() => {
    'perCoin': perCoin.map((key, c) => MapEntry(key, c.toJson())),
    'closedTrades': closedTrades,
    'winningTrades': winningTrades,
    'realizedTry': realizedTry,
    'totalBotFeesTry': totalBotFeesTry,
    'grossWinTry': grossWinTry,
    'grossLossTry': grossLossTry,
  };

  factory ProfitLearning.fromJson(Map<String, dynamic> json) {
    final coins = <String, CoinOutcome>{};
    final raw = json['perCoin'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          coins[entry.key.toString()] =
              CoinOutcome.fromJson(Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }
    double finite(dynamic n) {
      final v = (n as num?)?.toDouble() ?? 0;
      return v.isFinite ? v : 0;
    }
    return ProfitLearning(
      perCoin: coins,
      closedTrades: math.max(0, (json['closedTrades'] as num?)?.toInt() ?? 0),
      winningTrades: math.max(0, (json['winningTrades'] as num?)?.toInt() ?? 0),
      realizedTry: finite(json['realizedTry']),
      totalBotFeesTry: math.max(0, finite(json['totalBotFeesTry'])),
      grossWinTry: math.max(0, finite(json['grossWinTry'])),
      grossLossTry: math.max(0, finite(json['grossLossTry'])),
    );
  }
}
