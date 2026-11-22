import 'dart:async';
import 'package:flutter/material.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/market_service_v2.dart';
import '../services/portfolio_repository.dart';
import '../services/bot_store.dart';
import '../services/learning_bot.dart';
import 'bot_dashboard.dart';
import '../widgets/formatters.dart';
import '../widgets/mini_chart.dart';
import 'coin_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.cloudMode});
  final PortfolioRepository repository;
  final bool cloudMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _marketService = MarketService();
  StreamSubscription<LivePriceEvent>? _liveSubscription;
  Timer? _uiTimer;
  Timer? _botTimer;
  final _pendingLiveQuotes = <String, CoinQuote>{};
  String _feedStatus = 'Veri akışına bağlanılıyor';
  String _shownFeedStatus = 'Bağlantı bekleniyor';
  bool _manualTradeOpen = false;
  DateTime? _lastBotRun;
  final _botStore = BotStore();
  BotState? _botState;
  bool _botBusy = false;
  String? _botError;
  String? _botMessage;
  final _quotes = <String, CoinQuote>{};
  Portfolio? _portfolio;
  Timer? _refreshTimer;
  bool _loadingMarket = true;
  bool _busy = false;
  String? _marketError;
  String? _walletError;
  DateTime? _marketFetchedAt;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveSubscription = _marketService.liveEvents.listen(_receiveLiveEvent);
    _marketService.startLive();
    _uiTimer = Timer.periodic(
      const Duration(seconds: 2), (_) => _flushLiveUpdates(),
    );
    _loadPortfolio();
    _loadBot();
    _loadMarket();
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _botTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_marketService.isLive) _loadMarket();
    });
    _botTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _runBotCycle();
    });
  }

  void _receiveLiveEvent(LivePriceEvent event) {
    if (!mounted) return;
    _feedStatus = event.status;
    final quote = event.quote;
    if (quote != null) {
      _pendingLiveQuotes[quote.id] = quote;
    }
  }

  void _flushLiveUpdates() {
    if (!mounted) return;
    if (_pendingLiveQuotes.isEmpty) {
      if (_feedStatus != _shownFeedStatus) {
        setState(() => _shownFeedStatus = _feedStatus);
      }
      return;
    }
    final current = Map<String, CoinQuote>.from(_pendingLiveQuotes);
    _pendingLiveQuotes.clear();
    setState(() {
      for (final entry in current.entries) {
        final old = _quotes[entry.key];
        if (old == null || !old.updatedAt.isAfter(entry.value.updatedAt)) {
          _quotes[entry.key] = entry.value;
        }
      }
      _marketFetchedAt = DateTime.now();
      _shownFeedStatus = _marketService.sourceStatus;
      _loadingMarket = false;
      _marketError = null;
    });
    if (_botState?.enabled == true &&
        (_lastBotRun == null ||
          DateTime.now().difference(_lastBotRun!) >= const Duration(seconds: 45))) {
      _runBotCycle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _marketService.startLive();
      _startTimer();
      if (!_marketService.isLive) _loadMarket();
    } else {
      _marketService.stopLive();
      _refreshTimer?.cancel();
      _botTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _botTimer?.cancel();
    _uiTimer?.cancel();
    _liveSubscription?.cancel();
    _marketService.dispose();
    super.dispose();
  }

  Future<void> _loadPortfolio() async {
    try {
      final data = await widget.repository.load();
      if (mounted) {
        setState(() { _portfolio = data; _walletError = null; });
        await _runBotCycle();
      }
    } catch (error) {
      if (mounted) setState(() => _walletError = '$error');
    }
  }

  Future<void> _loadMarket() async {
    if (_busy || _marketService.isLive) return;
    _busy = true;
    if (mounted) setState(() => _loadingMarket = _quotes.isEmpty);
    try {
      final quotes = await _marketService.fetchQuotes();
      if (!mounted) return;
      setState(() {
        for (final quote in quotes) {
          final old = _quotes[quote.id];
          if (old == null || !old.updatedAt.isAfter(quote.updatedAt)) {
            _quotes[quote.id] = quote;
          }
        }
        _marketFetchedAt = DateTime.now();
        _shownFeedStatus = _marketService.sourceStatus;
        _marketError = null;
      });
      await _runBotCycle();
    } catch (error) {
      if (mounted) setState(() => _marketError = '$error');
    } finally {
      _busy = false;
      if (mounted) setState(() => _loadingMarket = false);
    }
  }


  Future<void> _loadBot() async {
    try {
      final state = await _botStore.load();
      if (!mounted) return;
      setState(() { _botState = state; _botError = null; });
      await _runBotCycle();
    } catch (error) {
      if (mounted) setState(() => _botError = 'Bot ayarları okunamadı: $error');
    }
  }

  Future<void> _setBotEnabled(bool enabled) async {
    if (_botBusy || _botState == null) return;
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Öğrenen sanal botu başlat?'),
          content: const Text(
            'Bot, açık olan tarayıcıda yeni fiyatlar geldikçe kendi kendine SANAL alış/satış yapabilir. '
            'İşlem başına %12, toplam pozisyonda %65 ve günde 8 işlem sınırı vardır. '
            'Sonuçları kâr garantisi değildir; kapalı tarayıcıda çalışmaz. '
            'Gerçek borsaya emir veya para transferi gönderilmez.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sanal botu aç')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    try {
      final next = _botState!.copyWith(enabled: enabled);
      await _botStore.save(next);
      if (!mounted) return;
      setState(() {
        _botState = next;
        _botError = null;
        _botMessage = enabled ? 'Piyasa verisiyle karar değerlendiriliyor.' : 'Bot durduruldu.';
      });
      if (enabled) await _runBotCycle();
    } catch (error) {
      if (mounted) setState(() => _botError = 'Bot ayarı kaydedilemedi: $error');
    }
  }

  Future<void> _runBotCycle() async {
    if (!mounted || _botBusy || _manualTradeOpen || _botState?.enabled != true ||
        _portfolio == null || _quotes.isEmpty ||
        (_marketError != null && !_marketService.isLive)) return;
    _lastBotRun = DateTime.now();
    _botBusy = true;
    setState(() => _botError = null);
    try {
      final evolved = observeBot(_botState!, _quotes.values);
      final order = planBotOrder(
        state: evolved,
        wallet: _portfolio!,
        quotes: _quotes,
      );

      if (order == null) {
        await _botStore.save(evolved);
        if (mounted) setState(() {
          _botState = evolved;
          _botMessage = 'Yeni sinyal bekleniyor veya risk limitleri devrede.';
        });
      } else {
        // Use the exact same validated virtual wallet pathway as manual orders.
        final wallet = await widget.repository.placeOrder(
          quote: order.quote,
          side: order.side,
          amountTry: order.amountTry,
        );
        final recorded = botRecordedTrade(evolved, order);
        await _botStore.save(recorded);
        if (mounted) setState(() {
          _portfolio = wallet;
          _botState = recorded;
          _botMessage = (order.side == TradeSide.buy ? 'Sanal AL • ' : 'Sanal SAT • ') +
              order.quote.symbol + ' • ' + order.reason;
        });
      }
    } catch (error) {
      if (mounted) setState(() {
        _botError = 'Bot işlemi yapılmadı: $error';
        _botMessage = 'Veri veya kayıt hatası nedeniyle işlem atlandı.';
      });
    } finally {
      _botBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refresh() async {
    _flushLiveUpdates();
    await Future.wait([_loadMarket(), _loadPortfolio()]);
  }

  Future<void> _openCoin(CoinQuote quote) async {
    final wallet = _portfolio;
    if (wallet == null) return;
    _manualTradeOpen = true;
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CoinDetailScreen(
        quote: quote,
        portfolio: wallet,
        repository: widget.repository,
      )),
    );
    _manualTradeOpen = false;
    if (success == true) {
      await _loadPortfolio();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sanal işlem tamamlandı.')),
      );
    }
  }

  Future<void> _resetPortfolio() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Portföyü sıfırla?'),
        content: const Text('Sanal cüzdan ₺650 bakiyeye döner; işlem geçmişi ve botun öğrendikleri silinir. Bot kapatılır. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sıfırla')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await widget.repository.reset();
      await _botStore.clear();
      if (mounted) setState(() {
        _botState = BotState.initial();
        _botMessage = 'Bot ve sanal portföy sıfırlandı.';
      });
      await _loadPortfolio();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sıfırlanamadı: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.candlestick_chart, color: Color(0xFF43D9A3)),
          SizedBox(width: 8), Text('SanalTrader', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(tooltip: 'Fiyatları yenile', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (value) { if (value == 'reset') _resetPortfolio(); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Portföyü sıfırla'))],
          ),
        ],
      ),
      body: Column(children: [
        _walletCard(),
        if (_marketError != null && !_marketService.isLive) _warning('Fiyat hatası: $_marketError'),
        if (_walletError != null) _warning('Cüzdan hatası: $_walletError'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: switch (_tab) {
              0 => _marketList(),
              1 => _holdingsList(),
              2 => _historyList(),
              _ => BotDashboard(
                state: _botState,
                busy: _botBusy,
                error: _botError,
                lastStatus: _botMessage,
                onEnabledChanged: _setBotEnabled,
              ),
            },
          ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Piyasa'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Portföy'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Geçmiş'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Bot'),
        ],
      ),
    );
  }

  Widget _warning(String message) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFF443026), borderRadius: BorderRadius.circular(10)),
    child: Text(message, style: const TextStyle(fontSize: 12, color: Color(0xFFFFD0A8))),
  );

  Widget _walletCard() {
    final wallet = _portfolio;
    final prices = _quotes.map((id, quote) => MapEntry(id, quote.priceTry));
    final total = wallet?.fullMarketValue(prices);
    final profit = total == null ? null : total - initialCashTry;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF233F42), Color(0xFF1B2738)]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('TOPLAM SANAL VARLIK', style: TextStyle(fontSize: 12, color: Colors.white70, letterSpacing: 1.2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF426B61), borderRadius: BorderRadius.circular(8)),
            child: Text(widget.cloudMode ? 'FIREBASE · DEMO' : 'YEREL · DEMO', style: const TextStyle(fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(total == null ? (_portfolio == null ? 'Yükleniyor...' : 'Fiyat bekleniyor') : formatTry(total),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metric('Sanal nakit', wallet == null ? '...' : formatTry(wallet.cashTry))),
          Expanded(child: _metric('Toplam getiri', profit == null ? '—' : '${profit >= 0 ? '+' : ''}${formatTry(profit)}',
              color: profit == null ? null : profit >= 0 ? const Color(0xFF43D9A3) : const Color(0xFFF27777))),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
    ],
  );

  Widget _marketList() {
    if (_loadingMarket && _quotes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final ordered = MarketService.coinIds
        .map((id) => _quotes[id]).whereType<CoinQuote>().toList();
    if (ordered.isEmpty) {
      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
        SizedBox(height: 80),
        Icon(Icons.wifi_off, size: 54, color: Colors.white38),
        SizedBox(height: 12),
        Center(child: Text('Piyasa verisi yok. Aşağı çekip yenile.')),
      ]);
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(children: [
          Text('Kripto piyasası', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(_marketFetchedAt == null ? '' : 'Alındı: ${TimeOfDay.fromDateTime(_marketFetchedAt!).format(context)}',
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(
            _marketService.isLive ? Icons.sensors : Icons.sync,
            size: 15,
            color: _marketService.isLive ? const Color(0xFF43D9A3) : Colors.orangeAccent,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(
            _shownFeedStatus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _marketService.isLive ? const Color(0xFF43D9A3) : Colors.white60,
              fontSize: 12,
            ),
          )),
        ]),
        const SizedBox(height: 10),
        for (final coin in ordered) _coinTile(coin),
      ],
    );
  }

  Widget _coinTile(CoinQuote quote) {
    final up = quote.change24h >= 0;
    return Card(
      color: const Color(0xFF19212D),
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCoin(quote),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF2B3545),
              child: Text(quote.symbol.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quote.symbol, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(quote.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ])),
            Expanded(flex: 2, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: MiniChart(prices: quote.sparkline, positive: up, height: 34),
            )),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
                child: Text(formatTry(quote.priceTry), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(formatChange(quote.change24h), style: TextStyle(fontSize: 12, color: up ? const Color(0xFF43D9A3) : const Color(0xFFF27777))),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _holdingsList() {
    final wallet = _portfolio;
    if (wallet == null) return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
      SizedBox(height: 60), Center(child: CircularProgressIndicator()),
    ]);
    final holdings = wallet.holdings.entries.where((entry) => entry.value.quantity > 0).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Varlıklarım', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _infoLine('Kullanılabilir bakiye', formatTry(wallet.cashTry)),
        _infoLine('Açık pozisyon maliyeti', formatTry(wallet.investedCostTry)),
        _infoLine('Gerçekleşmiş kâr/zarar', formatTry(wallet.realizedPnlTry)),
        const SizedBox(height: 10),
        if (holdings.isEmpty) const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: Text('Henüz coin almadın. Piyasa sekmesinden dene.', style: TextStyle(color: Colors.white54))),
        ),
        for (final item in holdings)
          Card(
            color: const Color(0xFF19212D),
            child: ListTile(
              title: Text(_quotes[item.key]?.symbol ?? item.key.toUpperCase()),
              subtitle: Text('${formatQuantity(item.value.quantity)} adet · Maliyet ${formatTry(item.value.costTry)}'),
              trailing: Text(_quotes[item.key] == null ? 'Fiyat yok' : formatTry(item.value.quantity * _quotes[item.key]!.priceTry)),
              onTap: _quotes[item.key] == null ? null : () => _openCoin(_quotes[item.key]!),
            ),
          ),
      ],
    );
  }

  Widget _infoLine(String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
      Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _historyList() {
    final trades = _portfolio?.trades ?? const <TradeRecord>[];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text('İşlem geçmişi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (trades.isEmpty) const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: Text('Henüz işlem yok.', style: TextStyle(color: Colors.white54))),
        ),
        for (final trade in trades)
          Card(
            color: const Color(0xFF19212D),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: trade.side == TradeSide.buy ? const Color(0xFF205647) : const Color(0xFF593535),
                child: Icon(trade.side == TradeSide.buy ? Icons.south_west : Icons.north_east,
                  color: trade.side == TradeSide.buy ? const Color(0xFF43D9A3) : const Color(0xFFF27777)),
              ),
              title: Text('${trade.side == TradeSide.buy ? 'AL' : 'SAT'} · ${trade.symbol}'),
              subtitle: Text('${trade.executedAt.day}.${trade.executedAt.month}.${trade.executedAt.year} '
                '${trade.executedAt.hour.toString().padLeft(2, '0')}:${trade.executedAt.minute.toString().padLeft(2, '0')} '
                '· Ücret ${formatTry(trade.feeTry)}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${trade.side == TradeSide.buy ? '-' : '+'}${formatTry(trade.cashChangeTry.abs())}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${formatQuantity(trade.quantity)} ${trade.symbol}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
          ),
      ],
    );
  }
}
