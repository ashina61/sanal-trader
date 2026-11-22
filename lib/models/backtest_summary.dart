/// Hypothetical, out-of-sample, fee-inclusive simulation results.
/// Never confuse these with completed virtual wallet orders.
class BacktestSummary {
  const BacktestSummary({
    required this.coins,
    required this.closedTrades,
    required this.winningTrades,
    required this.strategyReturnPct,
    required this.buyHoldReturnPct,
    required this.maxDrawdownPct,
    required this.evaluatedAt,
  });

  final int coins;
  final int closedTrades;
  final int winningTrades;
  final double strategyReturnPct;
  final double buyHoldReturnPct;
  final double maxDrawdownPct;
  final DateTime evaluatedAt;

  double? get winRate => closedTrades == 0
      ? null : winningTrades / closedTrades;

  Map<String, dynamic> toJson() => {
    'coins': coins,
    'closedTrades': closedTrades,
    'winningTrades': winningTrades,
    'strategyReturnPct': strategyReturnPct,
    'buyHoldReturnPct': buyHoldReturnPct,
    'maxDrawdownPct': maxDrawdownPct,
    'evaluatedAt': evaluatedAt.toUtc().millisecondsSinceEpoch,
  };

  factory BacktestSummary.fromJson(Map<String, dynamic> json) {
    double finite(dynamic value) {
      final n = (value as num?)?.toDouble() ?? 0.0;
      return n.isFinite ? n : 0.0;
    }
    return BacktestSummary(
      coins: ((json['coins'] as num?)?.toInt() ?? 0).clamp(0, 10000),
      closedTrades: ((json['closedTrades'] as num?)?.toInt() ?? 0).clamp(0, 100000),
      winningTrades: ((json['winningTrades'] as num?)?.toInt() ?? 0).clamp(0, 100000),
      strategyReturnPct: finite(json['strategyReturnPct']),
      buyHoldReturnPct: finite(json['buyHoldReturnPct']),
      maxDrawdownPct: finite(json['maxDrawdownPct']).clamp(0, 100).toDouble(),
      evaluatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['evaluatedAt'] as num?)?.toInt() ?? 0, isUtc: true),
    );
  }
}
