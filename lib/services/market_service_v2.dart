import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/coin_quote.dart';
import 'live_market_data.dart';

/// Public market data only. No account keys, trade endpoints or deposits.
class LivePriceEvent {
  const LivePriceEvent({this.quote, required this.status});
  final CoinQuote? quote;
  final String status;
}

class MarketService {
  MarketService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _liveEvents = StreamController<LivePriceEvent>.broadcast();
  Stream<LivePriceEvent> get liveEvents => _liveEvents.stream;
  static const coinIds = [
    'bitcoin', 'ethereum', 'solana', 'ripple', 'binancecoin', 'dogecoin',
  ];

  final _tickers = <String, MarketMiniTick>{};
  final _snapshots = <String, CoinQuote>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _retryTimer;
  bool _paused = true;
  bool _connecting = false;
  bool _disposed = false;
  bool _connected = false;
  DateTime? _lastTickTime;
  String _sourceStatus = 'Piyasa bekleniyor';

  bool get isLive => _connected && _lastTickTime != null &&
      DateTime.now().toUtc().difference(_lastTickTime!) < const Duration(seconds: 30);
  String get sourceStatus => isLive ? 'CANLI • Binance WebSocket (USDT/TRY)' : _sourceStatus;

  /// Fetch initial chart history and prices; Binance REST primary, CoinGecko fallback.
  Future<List<CoinQuote>> fetchQuotes() async {
    try {
      final quotes = await _fetchBinanceQuotes();
      for (final q in quotes) {
        final old = _snapshots[q.id];
        if (old == null || !old.updatedAt.isAfter(q.updatedAt)) _snapshots[q.id] = q;
      }
      _sourceStatus = 'Binance • güncel REST fiyatı';
      return quotes;
    } catch (binanceError) {
      try {
        final quotes = await _fetchCoinGeckoQuotes();
        for (final q in quotes) {
          final old = _snapshots[q.id];
          if (old == null || !old.updatedAt.isAfter(q.updatedAt)) _snapshots[q.id] = q;
        }
        _sourceStatus = 'CoinGecko • yedek veri (canlı değil)';
        return quotes;
      } catch (geckoError) {
        _sourceStatus = 'Piyasa verisi erişilemiyor';
        throw Exception('Binance: $binanceError • CoinGecko: $geckoError');
      }
    }
  }

  Future<List<CoinQuote>> _fetchBinanceQuotes() async {
    final symbols = [...trackedPairs.keys, 'USDTTRY'];
    final uri = Uri.https('data-api.binance.vision', '/api/v3/ticker/24hr', {
      'symbols': jsonEncode(symbols),
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final raw = jsonDecode(response.body);
    if (raw is! List) throw const FormatException('Binance ticker formatı bozuk');
    final tickerMap = <String, Map<String, dynamic>>{};
    for (final entry in raw) {
      if (entry is Map && entry['symbol'] != null) {
        tickerMap[entry['symbol'].toString()] = Map<String, dynamic>.from(entry);
      }
    }
    final rateTick = _tickerFromRest(tickerMap['USDTTRY'], 'USDTTRY');
    if (rateTick == null) throw Exception('USDT/TRY kuru alınamadı');
    final now = DateTime.now().toUtc();
    final futures = trackedPairs.entries.map((entry) async {
      final coin = _tickerFromRest(tickerMap[entry.key], entry.key);
      if (coin == null) return null;
      final history = await _fetchHourlyHistory(entry.key, rateTick.close);
      final q = marketQuoteFromTicks(coin: coin, tryRate: rateTick);
      if (q == null) return null;
      return CoinQuote(
        id: q.id,
        symbol: q.symbol,
        name: q.name,
        priceTry: q.priceTry,
        change24h: q.change24h,
        // REST response was observed now, but never treated as a future price.
        updatedAt: q.updatedAt.isAfter(now) ? now : q.updatedAt,
        sparkline: history,
      );
    });
    final quotes = (await Future.wait(futures)).whereType<CoinQuote>().toList();
    if (quotes.isEmpty) throw Exception('Binance fiyatları boş döndü');
    return quotes;
  }

  MarketMiniTick? _tickerFromRest(Map<String, dynamic>? raw, String symbol) {
    if (raw == null) return null;
    final last = double.tryParse('${raw['lastPrice']}');
    final open = double.tryParse('${raw['openPrice']}');
    if (last == null || !last.isFinite || last <= 0 ||
        open == null || !open.isFinite || open <= 0) return null;
    final timeMs = (raw['closeTime'] as num?)?.toInt();
    final now = DateTime.now().toUtc();
    final date = timeMs == null ? now : DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true);
    if (now.difference(date) > const Duration(minutes: 2)) return null;
    return MarketMiniTick(
      symbol: symbol, close: last, open: open, time: date.isAfter(now) ? now : date,
    );
  }

  Future<List<double>> _fetchHourlyHistory(String symbol, double tryRate) async {
    try {
      final uri = Uri.https('data-api.binance.vision', '/api/v3/klines', {
        'symbol': symbol, 'interval': '1h', 'limit': '168',
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final raw = jsonDecode(response.body);
      if (raw is! List) return [];
      return raw.whereType<List>().map((row) {
        if (row.length < 5) return 0.0;
        return (double.tryParse('${row[4]}') ?? 0) * tryRate;
      }).where((p) => p.isFinite && p > 0).toList();
    } catch (_) {
      return []; // No fabricated historical candles on API failure.
    }
  }

  Future<List<CoinQuote>> _fetchCoinGeckoQuotes() async {
    final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
      'vs_currency': 'try',
      'ids': coinIds.join(','),
      'order': 'market_cap_desc',
      'per_page': '10',
      'page': '1',
      'sparkline': 'true',
    });
    final response = await _client.get(uri, headers: {
      'accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final raw = jsonDecode(response.body);
    if (raw is! List) throw const FormatException('CoinGecko formatı bozuk');
    final data = raw.whereType<Map<String, dynamic>>().map(CoinQuote.fromJson)
        .where((q) => q.priceTry.isFinite && q.priceTry > 0).toList();
    if (data.isEmpty) throw Exception('CoinGecko boş yanıt');
    return data;
  }

  /// Start exchange-hosted, keyless streaming; reconnect on network interruptions.
  void startLive() {
    if (_disposed) return;
    _paused = false;
    if (_channel != null || _connecting) return;
    _connect();
  }

  Future<void> _connect() async {
    if (_paused || _disposed || _connecting) return;
    _connecting = true;
    _retryTimer?.cancel();
    _publishStatus('Canlı veri bağlantısı kuruluyor…');
    try {
      final pairs = [...trackedPairs.keys, 'USDTTRY'];
      final streams = pairs.map((s) => '${s.toLowerCase()}@miniTicker').join('/');
      final uri = Uri.parse('wss://data-stream.binance.vision/stream?streams=$streams');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));
      if (_paused || _disposed || _channel != channel) {
        await channel.sink.close();
        return;
      }
      _connected = true;
      _publishStatus('Canlı fiyat akışı bağlandı');
      _socketSubscription = channel.stream.listen(
        _onMarketMessage,
        onError: (_) => _handleDisconnect(channel),
        onDone: () => _handleDisconnect(channel),
        cancelOnError: true,
      );
    } catch (_) {
      _connected = false;
      _channel = null;
      _publishStatus('Canlı bağlantı yok • yedek fiyat yenilemesi');
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _onMarketMessage(dynamic raw) {
    final tick = MarketMiniTick.parse(raw);
    if (tick == null) return;
    _lastTickTime = DateTime.now().toUtc();
    _tickers[tick.symbol] = tick;
    final rate = _tickers['USDTTRY'];
    if (rate == null) return; // Never assume or fabricate a TRY exchange rate.

    final pairs = tick.symbol == 'USDTTRY' ? trackedPairs.keys : [tick.symbol];
    for (final pair in pairs) {
      final coin = _tickers[pair];
      if (coin == null) continue;
      final id = trackedPairs[pair];
      final quote = marketQuoteFromTicks(
        coin: coin, tryRate: rate, previous: id == null ? null : _snapshots[id],
      );
      if (quote == null) continue;
      _snapshots[quote.id] = quote;
      if (!_liveEvents.isClosed) _liveEvents.add(
        LivePriceEvent(quote: quote, status: sourceStatus),
      );
    }
  }

  void _handleDisconnect(WebSocketChannel source) {
    if (_channel != source || _disposed) return;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel = null;
    _connected = false;
    _publishStatus('Canlı bağlantı kesildi • yeniden bağlanıyor');
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_paused || _disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 12), _connect);
  }

  void _publishStatus(String status) {
    _sourceStatus = status;
    if (!_liveEvents.isClosed) _liveEvents.add(
      LivePriceEvent(status: status),
    );
  }

  void stopLive() {
    _paused = true;
    _connected = false;
    _retryTimer?.cancel();
    _socketSubscription?.cancel();
    _socketSubscription = null;
    final ch = _channel;
    _channel = null;
    ch?.sink.close();
  }

  void dispose() {
    _disposed = true;
    stopLive();
    _liveEvents.close();
    _client.close();
  }
}
