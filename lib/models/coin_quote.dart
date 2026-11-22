class CoinQuote {
  const CoinQuote({
    required this.id,
    required this.symbol,
    required this.name,
    required this.priceTry,
    required this.change24h,
    required this.updatedAt,
    required this.sparkline,
  });

  final String id;
  final String symbol;
  final String name;
  final double priceTry;
  final double change24h;
  final DateTime updatedAt;
  final List<double> sparkline;

  bool get isFresh {
    final elapsed = DateTime.now().toUtc().difference(updatedAt.toUtc());
    return elapsed >= Duration.zero && elapsed < const Duration(minutes: 10);
  }

  factory CoinQuote.fromJson(Map<String, dynamic> json) {
    final rawSparkline = json['sparkline_in_7d'];
    final points = rawSparkline is Map ? rawSparkline['price'] : null;
    return CoinQuote(
      id: json['id'] as String,
      symbol: (json['symbol'] as String).toUpperCase(),
      name: json['name'] as String,
      priceTry: (json['current_price'] as num).toDouble(),
      change24h: (json['price_change_percentage_24h'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['last_updated'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sparkline: points is List
          ? points.whereType<num>().map((point) => point.toDouble()).toList()
          : const [],
    );
  }
}
