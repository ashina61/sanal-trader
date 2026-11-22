import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/market_service_v2.dart';
import '../services/portfolio_repository.dart';
import '../services/bot_store.dart';
import '../services/learning_bot.dart';
import '../services/bot_training.dart';
import '../services/walk_forward_backtest.dart';
import 'bot_dashboard.dart';
import '../widgets/server_paper_card.dart';
import '../widgets/server_paper_overview.dart';
import '../services/server_paper_repository.dart';
import 'market_radar_screen.dart';
import 'bot_performance_screen.dart';
import 'update_history_screen.dart';
import '../widgets/formatters.dart';
import '../widgets/premium_dashboard.dart';
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
  final _serverRepo = ServerPaperRepository();
  final ValueNotifier<ServerPaperSnapshot?> _serverLive = ValueNotifier(null);
  ServerPaperSnapshot? _serverSnapshot;
  String? _serverError;
  bool _serverBusy = false;
  Timer? _serverTimer;
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
  DateTime? _lastHistoricalRefresh;
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
    _loadServer();
    _serverTimer = Timer.periodic(
      const Duration(minutes: 1), (_) => _loadServer(),
    );
    _loadBot();
    _loadMarket();
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _botTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      final dueHistory = _lastHistoricalRefresh == null ||
          DateTime.now().difference(_lastHistoricalRefresh!) >
              const Duration(hours: 1);
      if (!_marketService.isLive ||
          _botState?.trainingVersion != 1 || dueHistory) {
        _loadMarket();
      }
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
    // Web tab backgrounding must not deliberately turn off a user-enabled
    // paper bot. Browser throttling can still slow timers in hidden tabs.
    if (kIsWeb && state != AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.resumed) {
      _marketService.startLive();
      _startTimer();
      _loadServer();
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
    _serverTimer?.cancel();
    _serverRepo.dispose();
    _serverLive.dispose();
    _uiTimer?.cancel();
    _liveSubscription?.cancel();
    _marketService.dispose();
    super.dispose();
  }

  Future<void> _loadServer() async {
    if (_serverBusy || !mounted) return;
    _serverBusy = true;
    setState(() {});
    try {
      final result = await _serverRepo.load();
      if (!mounted) return;
      setState(() {
        _serverSnapshot = result;
        _serverLive.value = result;
        _serverError = null;
      });
    } catch (error) {
      if (mounted) {
        // Preserve the last good snapshot but clearly report stale/failed
        // refreshes. Never replace server data with local bot state.
        setState(() => _serverError = error.toString());
      }
    } finally {
      _serverBusy = false;
      if (mounted) setState(() {});
    }
  }

  void _openServerTrades() => Navigator.push(context, MaterialPageRoute<void>(
    builder: (_) => ServerPaperTradesScreen(
      snapshots: _serverLive,
      onRefresh: _loadServer,
    ),
  ));

  Widget _serverSummary() => ServerPaperSummaryTile(
    snapshot: _serverSnapshot,
    loading: _serverBusy,
    error: _serverError,
    onTap: () => setState(() => _tab = 3),
  );

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
    final historyDue = _lastHistoricalRefresh == null ||
        DateTime.now().difference(_lastHistoricalRefresh!) >
            const Duration(hours: 1);
    if (_busy || (_marketService.isLive &&
        _botState?.trainingVersion == 1 && !historyDue)) return;
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
          } else if (quote.sparkline.length > old.sparkline.length ||
              (quote.candles.isNotEmpty &&
               (old.candles.isEmpty ||
                quote.candles.last.time.isAfter(old.candles.last.time)))) {
            // Newer closed hourly history can arrive after a live spot tick.
            // Keep the live price but replace outdated charts.
            _quotes[quote.id] = CoinQuote(
              id: old.id, symbol: old.symbol, name: old.name,
              priceTry: old.priceTry, change24h: old.change24h,
              updatedAt: old.updatedAt,
              sparkline: [
                ...quote.sparkline.take(quote.sparkline.length - 1),
                old.priceTry,
              ],
              volume24hUsdt: quote.volume24hUsdt > 0
                  ? quote.volume24hUsdt : old.volume24hUsdt,
              candles: quote.candles.isNotEmpty &&
                  (old.candles.isEmpty ||
                   quote.candles.last.time.isAfter(old.candles.last.time))
                  ? quote.candles : old.candles,
            );
          }
        }
        _marketFetchedAt = DateTime.now();
        _lastHistoricalRefresh = DateTime.now();
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

  Future<void> _retrainBot() async {
    if (_botBusy || _botState == null) return;
    try {
      // Reset only historical training status. The real executed-trade
      // profit ledger and the user's pause/resume choice stay untouched.
      final reset = _botState!.copyWith(trainingVersion: 0);
      await _botStore.save(reset);
      if (!mounted) return;
      setState(() {
        _botState = reset;
        _botMessage = reset.enabled
            ? 'Yeni geçmiş verilerle eğitim başlatıldı.'
            : 'Eğitim işaretlendi; bot tekrar açılınca çalışacak.';
        _botError = null;
      });
      if (reset.enabled) {
        await _loadMarket();
        await _runBotCycle();
      }
    } catch (error) {
      if (mounted) setState(
        () => _botError = 'Yeniden eğitim isteği kaydedilemedi: $error');
    }
  }

  Future<void> _runBotCycle() async {
    if (!mounted || _botBusy || _manualTradeOpen || _botState?.enabled != true ||
        _portfolio == null || _quotes.isEmpty ||
        (_marketError != null && !_marketService.isLive)) return;
    // If WebSocket drops, stop trading until a fresh REST snapshot arrives.
    if (!_marketService.isLive &&
        (_marketFetchedAt == null ||
          DateTime.now().difference(_marketFetchedAt!) >
            const Duration(minutes: 2))) return;
    _lastBotRun = DateTime.now();
    _botBusy = true;
    setState(() => _botError = null);
    try {
      var starting = _botState!;
      final pricedWallet = _portfolio!.fullMarketValue({
        for (final q in _quotes.values)
          if (q.isFresh) q.id: q.priceTry,
      });
      if (pricedWallet != null && pricedWallet.isFinite &&
          pricedWallet > starting.peakEquityTry) {
        starting = starting.copyWith(peakEquityTry: pricedWallet);
      }
      final needsTraining = starting.trainingVersion < 1;
      if (needsTraining) {
        final training = trainHistoricalBot(_quotes.values);
        if (training == null) {
          if (mounted) setState(() {
            _botMessage = 'Geçmiş veriden eğitim bekleniyor; yeterli fiyat geçmişi yok.';
          });
          return;
        }
        starting = starting.copyWith(
          weights: training.weights,
          trainingVersion: 1,
          trainingExamples: training.trainingExamples,
          holdoutExamples: training.holdoutExamples,
          holdoutCorrect: training.holdoutCorrect,
          baselineCorrect: training.baselineCorrect,
          trainedCoins: training.coins,
        );
        await _botStore.save(starting);
        if (mounted) setState(() {
          _botState = starting;
          _botMessage = '${training.coins} coinin geçmişiyle eğitim tamamlandı.';
        });
      }
      // Revalidate at most hourly, using the already trained weights.
      // Hypothetical test outcomes remain separate from actual paper trades.
      final dueBacktest = needsTraining || starting.backtest == null ||
          DateTime.now().toUtc().difference(starting.backtest!.evaluatedAt) >
              const Duration(hours: 1);
      if (dueBacktest) {
        final result = walkForwardBacktest(
          _quotes.values, weights: starting.weights,
        );
        if (result != null) {
          starting = starting.copyWith(backtest: result);
        }
      }
      final evolved = observeBot(starting, _quotes.values);
      final order = planBotOrder(
        state: evolved,
        wallet: _portfolio!,
        quotes: _quotes,
      );

      if (order == null) {
        await _botStore.save(evolved);
        if (mounted) setState(() {
          _botState = evolved;
          _botMessage = '${_quotes.values.where((q) => q.isFresh).length} güncel coin izleniyor; '
              'uygun sinyal veya risk koşulu bekleniyor.';
        });
      } else {
        // Use the exact same validated virtual wallet pathway as manual orders.
        final wallet = await widget.repository.placeOrder(
          quote: order.quote,
          side: order.side,
          amountTry: order.amountTry,
        );
        // Realized profit-learning only uses the actual committed virtual
        // transaction returned by the repository, never a hypothetical fill.
        final actual = wallet.trades.isNotEmpty &&
            (_portfolio!.trades.isEmpty ||
                wallet.trades.first.id != _portfolio!.trades.first.id)
            ? wallet.trades.first : null;
        final recorded = botRecordedTrade(
          evolved, order, executedTrade: actual,
        );
        await _botStore.save(recorded);
        if (mounted) setState(() {
          _portfolio = wallet;
          _botState = recorded;
          final sale = actual != null && actual.side == TradeSide.sell
              ? ' • Net ${actual.realizedPnlTry.toStringAsFixed(2)} TL' : '';
          _botMessage = (order.side == TradeSide.buy ? 'Sanal AL • ' : 'Sanal SAT • ') +
              order.quote.symbol + ' • ' + order.reason + sale;
        });
      }
    } catch (error) {
      if (mounted) setState(() {
        // Fail closed: don't repeatedly submit orders after a storage error.
        _botState = _botState?.copyWith(enabled: false);
        _botError = 'Bot güvenlik nedeniyle durduruldu: $error';
        _botMessage = 'Veri veya kayıt hatası; bot kapatıldı.';
      });
      if (_botState != null) {
        try { await _botStore.save(_botState!); } catch (_) {}
      }
    } finally {
      _botBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refresh() async {
    _flushLiveUpdates();
    await Future.wait([_loadMarket(), _loadPortfolio(), _loadServer()]);
  }

  Future<void> _openCoin(CoinQuote quote) async {
    if (_manualTradeOpen || _botBusy) return;
    final wallet = _portfolio;
    if (wallet == null) return;
    _manualTradeOpen = true;
    try {
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CoinDetailScreen(
          quote: quote,
          portfolio: wallet,
          repository: widget.repository,
        )),
      );
      if (success == true) {
        await _loadPortfolio();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yerel sanal spot işlem tamamlandı.')),
        );
      }
    } finally {
      _manualTradeOpen = false;
    }
  }

  Future<void> _resetPortfolio() async {
    // Never reset the local wallet while an automatic paper fill or a
    // manual order is in flight. This operation does NOT touch the server.
    if (_botBusy || _manualTradeOpen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Devam eden sanal işlem bitmeden yerel kasa sıfırlanamaz.'),
      ));
      return;
    }
    _manualTradeOpen = true;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yalnızca yerel kasayı sıfırla?'),
          content: const Text(
            'Tarayıcıdaki yerel sanal cüzdan 650 TL’ye döner; '
            'YEREL işlem geçmişi ve YEREL botun öğrendikleri silinir. '
            'Ücretsiz sunucu botunun bakiyesi, LONG/SHORT pozisyonları '
            've geçmişi KESİNLİKLE ETKİLENMEZ. '
            'Bu yerel sıfırlama geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yerel Kasayı Sıfırla'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      try {
        // Disable the local auto bot before mutating its local wallet.
        await _botStore.save((_botState ?? BotState.initial())
            .copyWith(enabled: false));
        await widget.repository.reset();
        await _botStore.clear();
        if (!mounted) return;
        setState(() {
          _botState = BotState.initial();
          _botMessage = 'Yalnızca yerel sanal cüzdan sıfırlandı.';
        });
        await _loadPortfolio();
      } catch (error) {
        if (mounted) {
          setState(() => _botState = _botState?.copyWith(enabled: false));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Yerel sıfırlama tamamlanamadı: $error'),
          ));
        }
      }
    } finally {
      _manualTradeOpen = false;
    }
  }

  void _openUpdates() => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => const UpdateHistoryScreen(),
      ));

  void _openTrades() => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Yerel sanal işlem geçmişi')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: _historyList(),
            ),
          ),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 16,
        title: Row(children: [
          const Icon(Icons.candlestick_chart, color: PremiumColors.gold, size: 27),
          const SizedBox(width: 9),
          const Flexible(child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Sanal', style: TextStyle(
              fontWeight: FontWeight.w900, color: Colors.white)),
            TextSpan(text: 'Trader', style: TextStyle(
              fontWeight: FontWeight.w900, color: PremiumColors.gold)),
          ]), style: TextStyle(fontSize: 20), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Güncelleme Geçmişi',
            onPressed: _openUpdates,
            icon: const Icon(Icons.notifications_none, size: 22),
          ),
          IconButton(
            tooltip: 'Fiyatları yenile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 22),
          ),
          PopupMenuButton<String>(
            tooltip: 'Diğer seçenekler',
            onSelected: (value) {
              if (value == 'reset') _resetPortfolio();
              if (value == 'updates') _openUpdates();
              if (value == 'trades') _openTrades();
              if (value == 'server_trades') _openServerTrades();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'updates',
                child: Text('Güncelleme geçmişi')),
              PopupMenuItem(value: 'trades',
                child: Text('Yerel işlem geçmişi')),
              PopupMenuItem(value: 'server_trades',
                child: Text('Sunucu işlem geçmişi')),
              PopupMenuItem(value: 'reset',
                child: Text('Yalnızca yerel sanal kasayı sıfırla')),
            ],
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1A16), PremiumColors.background, Color(0xFF0B1113)],
          ),
        ),
        child: Column(children: [
          if (_marketError != null && !_marketService.isLive)
            _warning('Fiyat hatası: $_marketError'),
          if (_walletError != null) _warning('Cüzdan hatası: $_walletError'),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: switch (_tab) {
                    0 => _marketList(),
                    1 => MarketRadarScreen(
                      quotes: _quotes,
                      onOpen: (coin) { _openCoin(coin); },
                    ),
                    2 => _holdingsList(),
                    3 => BotDashboard(
                      state: _botState,
                      quotes: _quotes,
                      wallet: _portfolio,
                      busy: _botBusy,
                      error: _botError,
                      lastStatus: _botMessage,
                      onEnabledChanged: _setBotEnabled,
                      onRetrain: _retrainBot,
                      serverBotCard: ServerPaperCard(
                        snapshot: _serverSnapshot,
                        loading: _serverBusy,
                        error: _serverError,
                        onRefresh: _loadServer,
                        onOpenTrades: _openServerTrades,
                      ),
                      onOpenPerformance: () => setState(() => _tab = 4),
                    ),
                    _ => BotPerformanceScreen(
                      wallet: _portfolio,
                      quotes: _quotes,
                      bot: _botState,
                      onViewTrades: _openTrades,
                      serverSnapshot: _serverSnapshot,
                      serverBusy: _serverBusy,
                      serverError: _serverError,
                      onViewServerTrades: _openServerTrades,
                    ),
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PremiumColors.background,
          border: Border(top: BorderSide(color: PremiumColors.border, width: .8)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          backgroundColor: PremiumColors.background,
          indicatorColor: PremiumColors.goldDim,
          height: 70,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard, color: PremiumColors.gold),
              label: 'Panel'),
            NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: PremiumColors.gold),
              label: 'Radar'),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet, color: PremiumColors.gold),
              label: 'Portföy'),
            NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy, color: PremiumColors.gold),
              label: 'Bot'),
            NavigationDestination(
              icon: Icon(Icons.query_stats_outlined),
              selectedIcon: Icon(Icons.query_stats, color: PremiumColors.gold),
              label: 'Kâr'),
          ],
        ),
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

  Widget _walletCard() => PremiumPortfolioCard(
        wallet: _portfolio,
        quotes: _quotes,
        cloudMode: widget.cloudMode,
      );

  Widget _marketList() {
    final ordered = _quotes.values.toList()
      ..sort((a, b) => b.volume24hUsdt.compareTo(a.volume24hUsdt));
    final btc = _quotes['bitcoin'];
    final featured = ordered.take(5).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
      children: [
        ServerPaperOverview(
          snapshot: _serverSnapshot,
          loading: _serverBusy,
          error: _serverError,
          onOpenBot: () => setState(() => _tab = 3),
          onOpenTrades: _openServerTrades,
          onRefresh: _loadServer,
        ),
        const SizedBox(height: 13),
        Card(
          color: PremiumColors.panel,
          child: ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Yerel demo kasası · ayrı hesap',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            subtitle: const Text('Ana botun değerine eklenmez',
              style: TextStyle(fontSize: 10, color: PremiumColors.muted)),
            childrenPadding: const EdgeInsets.all(10),
            children: [_walletCard()],
          ),
        ),
        const SizedBox(height: 18),
        PremiumSectionTitle(
          title: 'Piyasa Takip Listesi',
          trailing: TextButton(
            onPressed: () => setState(() => _tab = 1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Tümünü gör',
                style: const TextStyle(color: PremiumColors.gold, fontSize: 12)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right,
                color: PremiumColors.gold, size: 17),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        PremiumSurface(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: featured.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 30),
                  child: Center(
                    child: Column(children: [
                      if (_loadingMarket) const CircularProgressIndicator(),
                      const SizedBox(height: 11),
                      Text(_loadingMarket
                          ? 'Canlı piyasa verisi yükleniyor...'
                          : 'Fiyat verisi yok. Yenilemeyi deneyebilirsin.',
                        style: const TextStyle(
                          color: PremiumColors.muted, fontSize: 12)),
                    ]),
                  ),
                )
              : Column(children: [
                  for (var i = 0; i < featured.length; i++) ...[
                    PremiumMarketTile(
                      quote: featured[i],
                      onTap: () => _openCoin(featured[i]),
                    ),
                    if (i != featured.length - 1)
                      Divider(height: 1, thickness: .6,
                        indent: 11, endIndent: 11,
                        color: PremiumColors.border.withValues(alpha: .6)),
                  ],
                ]),
        ),
        const SizedBox(height: 9),
        Row(children: [
          Icon(_marketService.isLive
              ? Icons.sensors : Icons.sync_outlined,
            color: _marketService.isLive
                ? PremiumColors.emerald : PremiumColors.gold, size: 15),
          const SizedBox(width: 6),
          Expanded(child: Text(_shownFeedStatus,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PremiumColors.muted, fontSize: 11))),
          Text('${ordered.length} coin',
            style: const TextStyle(
              color: PremiumColors.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 23),
        PremiumSectionTitle(title: 'Otonom Bot Kontrolü'),
        const SizedBox(height: 10),
        PremiumSurface(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined,
              color: PremiumColors.gold),
            title: const Text('Ana bot · Groq + sunucu',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            subtitle: Text(
              _serverSnapshot?.decisionPlan['reason']?.toString() ??
                'Son sanal piyasa kararı bekleniyor',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PremiumColors.muted,
                fontSize: 11)),
            trailing: const Icon(Icons.chevron_right,
              color: PremiumColors.gold),
            onTap: () => setState(() => _tab = 3),
          ),
        ),
        const SizedBox(height: 22),
        PremiumSectionTitle(title: 'Teknik Göstergeler (BTC)'),
        const SizedBox(height: 10),
        if (btc != null)
          PremiumTechnicalOverview(
            quote: btc,
            onTap: () => _openCoin(btc),
          )
        else
          const PremiumSurface(
            child: Text('BTC geçmişi bekleniyor.',
              style: TextStyle(color: PremiumColors.muted)),
          ),
        const SizedBox(height: 18),
        PremiumUpdateTile(
          version: '0.9.7',
          onTap: _openUpdates,
        ),

      ],
    );
  }

  Widget _holdingsList() {
    final wallet = _portfolio;
    final holdings = wallet?.holdings.entries
        .where((entry) => entry.value.quantity > 0).toList() ?? [];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ServerPaperPositionsPanel(
          snapshot: _serverSnapshot,
          onOpenTrades: _openServerTrades,
        ),
        const SizedBox(height: 12),
        Card(
          color: PremiumColors.panel,
          child: ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Yerel demo portföyü · ayrı hesap',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            subtitle: const Text('Ana sunucu cüzdanından bağımsızdır',
              style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
            childrenPadding: const EdgeInsets.all(12),
            children: [
              if (wallet == null)
                const Padding(padding: EdgeInsets.all(15),
                  child: Center(child: CircularProgressIndicator())),
              if (wallet != null) ...[
                _walletCard(),
                const SizedBox(height: 12),
                _infoLine('Kullanılabilir bakiye', formatTry(wallet.cashTry)),
                _infoLine('Açık pozisyon maliyeti',
                  formatTry(wallet.investedCostTry)),
                _infoLine('Gerçekleşmiş kâr/zarar',
                  formatTry(wallet.realizedPnlTry)),
                if (holdings.isEmpty)
                  const Padding(padding: EdgeInsets.all(12),
                    child: Text('Yerel demo pozisyonu yok.',
                      style: TextStyle(color: PremiumColors.muted))),
                for (final item in holdings)
                  Card(color: PremiumColors.panelRaised,
                    child: ListTile(
                      title: Text(_quotes[item.key]?.symbol
                          ?? item.key.toUpperCase()),
                      subtitle: Text(
                        '${formatQuantity(item.value.quantity)} adet · '
                        'Maliyet ${formatTry(item.value.costTry)}'),
                      trailing: Text(_quotes[item.key] == null
                          ? 'Fiyat yok'
                          : !_quotes[item.key]!.isFresh
                              ? 'Fiyat bayat'
                              : formatTry(item.value.quantity
                                  * _quotes[item.key]!.priceTry)),
                      onTap: _quotes[item.key]?.isFresh != true
                          ? null : () => _openCoin(_quotes[item.key]!),
                    ),
                  ),
              ],
            ],
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
        Text('Yerel işlem geçmişi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (trades.isEmpty) const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: Text('Henüz işlem yok.', style: TextStyle(color: Colors.white54))),
        ),
        for (final trade in trades)
          Card(
            color: PremiumColors.panel,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: trade.side == TradeSide.buy ? PremiumColors.emeraldDim : const Color(0xFF593535),
                child: Icon(trade.side == TradeSide.buy ? Icons.south_west : Icons.north_east,
                  color: trade.side == TradeSide.buy ? PremiumColors.emerald : PremiumColors.danger),
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
