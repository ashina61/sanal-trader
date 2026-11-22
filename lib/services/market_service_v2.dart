import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/coin_quote.dart';
import 'live_market_data.dart';
import 'market_universe.dart';

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
  final _trackedPairs = <String, String>{...trackedPairs};
  final _volumes = <String, double>{};
  bool _universeLoaded = false;
  bool _historyReady = false;
  DateTime? _lastHistoryAttempt;
  int get universeSize => _trackedPairs.length;

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
        _snapshots[q.id] = _preferNewerWithHistory(_snapshots[q.id], q);
      }
      _sourceStatus = 'Binance • güncel REST fiyatı';
      return quotes;
    } catch (binanceError) {
      try {
        final quotes = await _fetchCoinGeckoQuotes();
        for (final q in quotes) {
          _snapshots[q.id] = _preferNewerWithHistory(_snapshots[q.id], q);
        }
        _sourceStatus = 'CoinGecko • yedek veri (canlı değil)';
        return quotes;
      } catch (geckoError) {
        _sourceStatus = 'Piyasa verisi erişilemiyor';
        throw Exception('Binance: $binanceError • CoinGecko: $geckoError');
      }
    }
  }

  CoinQuote _preferNewerWithHistory(CoinQuote? older, CoinQuote candidate) {
    if (older == null || !older.updatedAt.isAfter(candidate.updatedAt)) {
      return candidate;
    }
    if (candidate.sparkline.length <= older.sparkline.length) return older;
    return CoinQuote(
      id: older.id, symbol: older.symbol, name: older.name,
      priceTry: older.priceTry, change24h: older.change24h,
      updatedAt: older.updatedAt,
      sparkline: [
        ...candidate.sparkline.take(candidate.sparkline.length - 1),
        older.priceTry,
      ],
      volume24hUsdt: candidate.volume24hUsdt > 0
          ? candidate.volume24hUsdt : older.volume24hUsdt,
    );
  }

  Future<List<CoinQuote>> _fetchBinanceQuotes() async {
    // First boot discovers liquid USDT spot pairs without hardcoding listings.
    // Subsequent REST refreshes use only our selected symbols.
    final discover = !_universeLoaded;
    final uri = discover
        ? Uri.https('data-api.binance.vision', '/api/v3/ticker/24hr')
        : Uri.https('data-api.binance.vision', '/api/v3/ticker/24hr', {
            'symbols': jsonEncode([..._trackedPairs.keys, 'USDTTRY']),
          });
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ' + response.statusCode.toString());
    }
    final raw = jsonDecode(response.body);
    if (raw is! List) throw const FormatException('Binance ticker formatı bozuk');

    if (discover) {
      final selected = selectMarketUniverse(raw);
      if (selected.pairs.length < 6) {
        throw Exception('Yeterli hacimli USDT piyasası bulunamadı.');
      }
      _trackedPairs
        ..clear()
        ..addAll(selected.pairs);
      _volumes
        ..clear()
        ..addAll(selected.volumes);
      _universeLoaded = true;
      // Reconnect with the discovered 72-pair watchlist.
      final channel = _channel;
      if (channel != null) {
        stopLive();
        // The prior async connection may still be finishing; reconnect once
        // it has fully settled rather than silently losing the new universe.
        _paused = false;
        _scheduleRetry();
      }
    }

    final tickerMap = <String, Map<String, dynamic>>{};
    for (final entry in raw) {
      if (entry is Map && entry['symbol'] != null) {
        tickerMap[entry['symbol'].toString()] = Map<String, dynamic>.from(entry);
      }
    }
    final rateTick = _tickerFromRest(tickerMap['USDTTRY'], 'USDTTRY');
    if (rateTick == null) throw Exception('USDT/TRY kuru alınamadı');

    // Historical data is fetched for up to 36 most liquid pairs. Other coins
    // are visible with live prices but are not eligible for new bot buys.
    final ranked = _trackedPairs.keys.toList()
      ..sort((a, b) => (_volumes[b] ?? 0).compareTo(_volumes[a] ?? 0));
    final trainingPairs = ranked.take(36).toSet();
    final history = <String, List<double>>{};
    final shouldLoadHistory = !_historyReady &&
        (_lastHistoryAttempt == null ||
         DateTime.now().toUtc().difference(_lastHistoryAttempt!) >
           const Duration(minutes: 10));
    if (shouldLoadHistory) {
      _lastHistoryAttempt = DateTime.now().toUtc();
      for (var i = 0; i < ranked.length && i < 36; i += 6) {
        final batch = ranked.skip(i).take(6);
        final fetched = await Future.wait(batch.map((pair) async =>
          MapEntry(pair, await _fetchHourlyHistory(pair, rateTick.close))));
        history.addEntries(fetched);
      }
      _historyReady = history.values.where((prices) => prices.length >= 96).length >= 3;
    }

    final quotes = <CoinQuote>[];
    for (final pair in _trackedPairs.keys) {
      final coin = _tickerFromRest(tickerMap[pair], pair);
      if (coin == null) continue;
      final id = _trackedPairs[pair];
      final old = id == null ? null : _snapshots[id];
      final q = marketQuoteFromTicks(
        coin: coin, tryRate: rateTick, previous: old,
        pairs: _trackedPairs, volumes: _volumes,
      );
      if (q == null) continue;
      final chart = history[pair] ?? old?.sparkline ?? const <double>[];
      quotes.add(CoinQuote(
        id: q.id,
        symbol: q.symbol,
        name: q.name,
        priceTry: q.priceTry,
        change24h: q.change24h,
        updatedAt: q.updatedAt,
        sparkline: trainingPairs.contains(pair) ? chart : const <double>[],
        volume24hUsdt: q.volume24hUsdt,
      ));
    }
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
    // Broad market-cap fallback when Binance cannot be accessed. This is
    // scheduled REST data, not a live WebSocket feed.
    final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
      'vs_currency': 'try',
      'order': 'market_cap_desc',
      'per_page': '100',
      'page': '1',
      'sparkline': 'true',
    });
    final response = await _client.get(uri, headers: {
      'accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ' + response.statusCode.toString());
    }
    final raw = jsonDecode(response.body);
    if (raw is! List) throw const FormatException('CoinGecko formatı bozuk');
    final data = <CoinQuote>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final sym = (item['symbol'] as String?)?.toUpperCase() ?? '';
      // Avoid stables and leveraged/synthetic symbols on backup provider.
      if (!eligibleUsdtSpotSymbol(sym + 'USDT')) continue;
      final turnover = (item['total_volume'] as num?)?.toDouble();
      if (turnover == null || !turnover.isFinite || turnover < 50000000) {
        continue;
      }
      try {
        final q = CoinQuote.fromJson(item);
        if (q.priceTry.isFinite && q.priceTry > 0) data.add(q);
      } catch (_) {
        continue; // Ignore malformed individual symbols, not entire page.
      }
      if (data.length >= 72) break;
    }
    if (data.isEmpty) throw Exception('CoinGecko uygun coin döndürmedi');
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
      final pairs = [..._trackedPairs.keys, 'USDTTRY'];
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
    _tickers[tick.symbol] = tick;
    final rate = _tickers['USDTTRY'];
    if (rate == null) return; // Never assume or fabricate a TRY exchange rate.

    final pairs = tick.symbol == 'USDTTRY' ? _trackedPairs.keys : [tick.symbol];
    for (final pair in pairs) {
      final coin = _tickers[pair];
      if (coin == null) continue;
      final id = _trackedPairs[pair];
      final quote = marketQuoteFromTicks(
        coin: coin, tryRate: rate, previous: id == null ? null : _snapshots[id],
        pairs: _trackedPairs, volumes: _volumes,
      );
      if (quote == null) continue;
      _snapshots[quote.id] = quote;
      _lastTickTime = DateTime.now().toUtc();
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
