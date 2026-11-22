import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import 'portfolio_repository.dart';
import 'trade_engine.dart';

class LocalPortfolioRepository implements PortfolioRepository {
  LocalPortfolioRepository({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'sanal_trader_portfolio_v1';
  final SharedPreferencesAsync _prefs;

  @override
  Future<Portfolio> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return Portfolio.fresh();
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final tradesRaw = (json['trades'] as List?) ?? const [];
    final trades = tradesRaw
        .whereType<Map>()
        .map((entry) => TradeRecord.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    return Portfolio.fromJson(json, trades: trades);
  }

  @override
  Future<Portfolio> placeOrder({
    required CoinQuote quote,
    required TradeSide side,
    required double amountTry,
  }) async {
    final current = await load();
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
  }

  @override
  Future<void> reset() async => _prefs.remove(_key);
}
