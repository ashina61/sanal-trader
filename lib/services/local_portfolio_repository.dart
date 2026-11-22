import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import 'portfolio_repository.dart';
import 'trade_engine.dart';

/// Single-application-tab local paper wallet. All writes are serialized:
/// simultaneous bot and manual requests cannot overwrite one another.
/// Browser tabs do not share this mutex; server wallet remains independent.
class LocalPortfolioRepository implements PortfolioRepository {
  LocalPortfolioRepository({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'sanal_trader_portfolio_v1';
  final SharedPreferencesAsync _prefs;

  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<Portfolio> _readUnsafe() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return Portfolio.fresh();
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final tradesRaw = (data['trades'] as List?) ?? const [];
    final trades = tradesRaw
        .whereType<Map>()
        .map((entry) => TradeRecord.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    return Portfolio.fromJson(data, trades: trades);
  }

  @override
  Future<Portfolio> load() async {
    await _tail;
    return _readUnsafe();
  }

  @override
  Future<Portfolio> placeOrder({
    required CoinQuote quote,
    required TradeSide side,
    required double amountTry,
  }) => _locked(() async {
    final current = await _readUnsafe();
    final result = executeVirtualTrade(
      current: current,
      quote: quote,
      side: side,
      amountTry: amountTry,
    );
    final data = {
      ...result.portfolio.toJson(),
      'trades': result.portfolio.trades.map((trade) => trade.toJson()).toList(),
    };
    await _prefs.setString(_key, jsonEncode(data));
    return result.portfolio;
  });

  @override
  Future<void> reset() => _locked<void>(() => _prefs.remove(_key));
}
