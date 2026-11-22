import 'dart:convert';
import '../models/coin_quote.dart';

/// Validated public-market miniTicker data, never a trading/ordering channel.
class MarketMiniTick {
  const MarketMiniTick({
    required this.symbol,
    required this.close,
    required this.open,
    required this.time,
  });

  final String symbol;
  final double close;
  final double open;
  final DateTime time;

  /// Binance combined stream: { "stream": "...", "data": { "s": "BTCUSDT",
  /// "c": "...", "o": "...", "E": 1234567890000 } }.
  static MarketMiniTick? parse(dynamic source) {
    try {
      final message = source is String ? jsonDecode(source) : source;
      if (message is! Map) return null;
      final data = message['data'];
      if (data is! Map) return null;
      final symbol = data['s']?.toString() ?? '';
      final close = double.tryParse(data['c']?.toString() ?? '');
      final open = double.tryParse(data['o']?.toString() ?? '');
      final epoch = data['E'];
      if (symbol.isEmpty || close == null || !close.isFinite || close <= 0 ||
          open == null || !open.isFinite || open <= 0 ||
          epoch is! num || epoch.toInt() <= 0) return null;
      final now = DateTime.now().toUtc();
      final stamp = DateTime.fromMillisecondsSinceEpoch(epoch.toInt(), isUtc: true);
      // Reject stale ticks and ticks too far into the future.
      if (now.difference(stamp) > const Duration(minutes: 2) ||
          stamp.difference(now) > const Duration(seconds: 30)) return null;
      return MarketMiniTick(
        symbol: symbol,
        close: close,
        open: open,
        time: stamp.isAfter(now) ? now : stamp,
      );
    } catch (_) {
      return null;
    }
  }
}

const trackedPairs = <String, String>{
  'BTCUSDT': 'bitcoin',
  'ETHUSDT': 'ethereum',
  'SOLUSDT': 'solana',
  'XRPUSDT': 'ripple',
  'BNBUSDT': 'binancecoin',
  'DOGEUSDT': 'dogecoin',
};

const trackedSymbols = <String, String>{
  'BTCUSDT': 'BTC',
  'ETHUSDT': 'ETH',
  'SOLUSDT': 'SOL',
  'XRPUSDT': 'XRP',
  'BNBUSDT': 'BNB',
  'DOGEUSDT': 'DOGE',
};

const trackedNames = <String, String>{
  'bitcoin': 'Bitcoin',
  'ethereum': 'Ethereum',
  'solana': 'Solana',
  'ripple': 'XRP',
  'binancecoin': 'BNB',
  'dogecoin': 'Dogecoin',
};

CoinQuote? marketQuoteFromTicks({
  required MarketMiniTick coin,
  required MarketMiniTick tryRate,
  CoinQuote? previous,
  Map<String, String>? pairs,
  Map<String, double>? volumes,
}) {
  final id = (pairs ?? trackedPairs)[coin.symbol];
  if (id == null || coin.symbol == 'USDTTRY') return null;
  final priceTry = coin.close * tryRate.close;
  final oldTry = coin.open * tryRate.open;
  if (!priceTry.isFinite || priceTry <= 0 || !oldTry.isFinite || oldTry <= 0) return null;
  final current = coin.time.isBefore(tryRate.time) ? coin.time : tryRate.time;
  if (DateTime.now().toUtc().difference(current) > const Duration(minutes: 2)) return null;
  final prior = previous?.sparkline ?? const <double>[];
  // Keep the historical chart and replace its last candle with current spot.
  final chart = prior.length > 1 ? <double>[...prior.take(prior.length - 1), priceTry] :
    (prior.isEmpty ? <double>[] : <double>[priceTry]);
  return CoinQuote(
    id: id,
    symbol: trackedSymbols[coin.symbol] ?? coin.symbol.substring(0, coin.symbol.length - 4),
    name: trackedNames[id] ?? coin.symbol.substring(0, coin.symbol.length - 4),
    priceTry: priceTry,
    change24h: (priceTry / oldTry - 1) * 100,
    updatedAt: current,
    sparkline: chart,
    volume24hUsdt: volumes?[coin.symbol] ?? previous?.volume24hUsdt ?? 0,
  );
}
