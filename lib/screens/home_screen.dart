import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_paper_repository.dart';
import '../widgets/server_paper_card.dart';
import '../widgets/server_paper_overview.dart';
import '../widgets/server_runtime_status.dart';
import '../widgets/smart_money_card.dart';
import '../widgets/free_dex_radar_card.dart';
import '../widgets/premium_theme.dart';
import '../widgets/compact_wallet_card.dart';
import '../widgets/execution_pipeline_card.dart';
import '../widgets/trade_learning_card.dart';
import '../widgets/formatters.dart';
import 'update_history_screen.dart';

/// Single source of truth: only the autonomous GitHub paper wallet is read.
/// No browser-local wallet, local trading bot, manual exchange order or Firebase.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ServerPaperRepository _repo = ServerPaperRepository();
  final ValueNotifier<ServerPaperSnapshot?> _live = ValueNotifier(null);
  ServerPaperSnapshot? _snapshot;
  Timer? _poller;
  String? _error;
  bool _loading = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poller = Timer.periodic(const Duration(seconds: 60),
      (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    try {
      final next = await _repo.load();
      if (!mounted) return;
      setState(() {
        _snapshot = next;
        _live.value = next;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _repo.dispose();
    _live.dispose();
    super.dispose();
  }

  void _showTrades() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ServerPaperTradesScreen(
      snapshots: _live,
      onRefresh: _refresh,
    )));

  void _showUpdates() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const UpdateHistoryScreen()));

  Widget _panel() {
    final s = _snapshot;
    final plan = s?.decisionPlan ?? const <String, dynamic>{};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
      children: [
        CompactWalletCard(
          snapshot: s, error: _error, loading: _loading,
          onRefresh: _refresh, onTrades: _showTrades),
        const SizedBox(height: 9),
        PremiumSurface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.bolt_outlined,
                    size: 18, color: PremiumColors.gold),
                const SizedBox(width: 7),
                const Text('SON BOT KARARI', style: TextStyle(
                    color: PremiumColors.gold,
                    fontWeight: FontWeight.w800, fontSize: 11)),
                const Spacer(),
                Text(plan['action']?.toString() ?? 'WAIT',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 11)),
              ]),
              const SizedBox(height: 7),
              Text(plan['reason']?.toString() ??
                  'İlk karar bekleniyor.',
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 7),
              Row(children: [
                Expanded(child: _stat('Piyasa',
                  plan['marketRegime']?.toString() ?? '—')),
                Expanded(child: _stat('Tarama',
                  '${s?.tracked ?? 0} parite')),
                TextButton(onPressed: () => setState(() => _tab = 2),
                  child: const Text('Detay',
                    style: TextStyle(fontSize: 11))),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: false,
          leading: const Icon(Icons.layers_outlined,
              color: PremiumColors.gold, size: 18),
          title: Text('Açık pozisyonlar (${(s?.holdings.length ?? 0) + (s?.shorts.length ?? 0)})',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          children: [
            ServerPaperPositionsPanel(snapshot: s, onOpenTrades: _showTrades),
          ],
        )),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.monitor_heart_outlined,
              size: 18, color: PremiumColors.gold),
          title: const Text('Sistem ve tarama ayrıntıları',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          children: [
            ServerRuntimeStatusCard(snapshot: s, error: _error),
          ],
        )),
      ],
    );
  }

  Widget _radar() {
    final s = _snapshot;
    final plan = s?.decisionPlan ?? const <String, dynamic>{};
    final candidates = plan['candidates'] is List
      ? (plan['candidates'] as List).whereType<Map>().toList()
      : <Map>[];
    final rejected = plan['rejectReasons'];
    final rejectedMap = rejected is Map ? rejected : const {};
    final dex = s?.freeDexRadar ?? const <String, dynamic>{};
    final smart = s?.smartMoney ?? const <String, dynamic>{};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
      children: [
        const PremiumSectionTitle(title: 'Fırsat Radarı'),
        const SizedBox(height: 8),
        PremiumSurface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _stat('Likit parite',
                    '${s?.tracked ?? '—'}')),
                Expanded(child: _stat('Teknik aday',
                    '${candidates.length}')),
                Expanded(child: _stat('DEX havuzu',
                    '${dex['poolsScreened'] ?? '—'}')),
              ]),
              const SizedBox(height: 7),
              Text('Son sinyal: ${plan['reason'] ?? 'Tarama bekleniyor'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: PremiumColors.muted, fontSize: 11)),
              const SizedBox(height: 3),
              Text('Akıllı cüzdan doğrulaması: '
                  '${smart['status'] == 'READY' ? 'Veri geldi' : 'Veri kaynağı yok / yetersiz'}',
                  style: const TextStyle(fontSize: 10,
                      color: PremiumColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: candidates.isNotEmpty,
          leading: const Icon(Icons.candlestick_chart_outlined,
              size: 20, color: PremiumColors.gold),
          title: Text('Teknik fırsatlar (${candidates.length})',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          subtitle: const Text('Binance · 1dk / 15dk / saatlik',
              style: TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
          children: [
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 9),
                child: Text('Giriş şartlarını karşılayan aday yok.',
                    style: TextStyle(fontSize: 12,
                        color: PremiumColors.muted))),
            for (final item in candidates.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  Expanded(child: Text(
                      item['symbol']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w800))),
                  Text(item['action']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 11,
                          color: PremiumColors.gold)),
                  const SizedBox(width: 8),
                  Text('Puan: ${item['score'] ?? '—'}',
                      style: const TextStyle(fontSize: 11)),
                ]),
              ),
            if (rejectedMap.isNotEmpty)
              Material(color: Colors.transparent,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Elenen fırsatların nedenleri',
                      style: TextStyle(fontSize: 12)),
                  children: [
                    for (final item in rejectedMap.entries.take(8))
                      Padding(padding: const EdgeInsets.only(bottom: 5),
                        child: Row(children: [
                          Expanded(child: Text(item.key.toString(),
                              style: const TextStyle(fontSize: 11))),
                          Text('${item.value} parite',
                              style: const TextStyle(fontSize: 11,
                                  color: PremiumColors.muted)),
                        ])),
                  ],
                )),
          ],
        )),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.travel_explore_outlined,
              size: 20, color: PremiumColors.gold),
          title: const Text('Ücretsiz Solana + Base keşfi',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${dex['observedSenders'] ?? 0} adres · ${dex['tradesChecked'] ?? 0} işlem · '
              '${dex['status'] ?? 'İlk tarama'}',
              style: const TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
          children: [FreeDexRadarCard(snapshot: s)],
        )),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.hub_outlined,
              size: 20, color: PremiumColors.gold),
          title: const Text('Doğrulanmış Akıllı Para',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          subtitle: Text('${smart['status'] ?? 'NOT_CONFIGURED'} · Harici veri gerekir',
              style: const TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
          children: [SmartMoneyCard(snapshot: s)],
        )),
        const SizedBox(height: 8),
        const Text('DEX adres kümeleri alım sinyali değildir. '
            'Emir açma kararı tek kasa risk motorundadır.',
            style: TextStyle(fontSize: 10,
                color: PremiumColors.muted)),
      ],
    );
  }

  Widget _bot() {
    final s = _snapshot;
    final plan = s?.decisionPlan ?? const <String, dynamic>{};
    final ai = plan['aiBrain'] is Map ? plan['aiBrain'] as Map : const {};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
      children: [
        PremiumSurface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.smart_toy_outlined, size: 19,
                  color: PremiumColors.gold),
              const SizedBox(width: 7),
              const Expanded(child: Text('Bot Kontrol Merkezi',
                  style: TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w800))),
              Text(s?.enabled == false ? 'DURDU' :
                  s?.error != null ? 'HATA' : 'SANAL',
                  style: const TextStyle(
                      color: PremiumColors.gold,
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 7),
            Text(s == null ? 'Sunucu kontrolü bekleniyor'
                : s.runtimeLabelAt(DateTime.now()),
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(plan['reason']?.toString() ??
                'Henüz işlem kararı kaydedilmedi.',
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11,
                    color: PremiumColors.muted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _stat('Karar',
                  plan['action']?.toString() ?? 'WAIT')),
              Expanded(child: _stat('AI',
                  ai['status']?.toString() ?? '—')),
              Expanded(child: _stat('Açık işlem',
                  '${(s?.holdings.length ?? 0) + (s?.shorts.length ?? 0)}')),
            ]),
          ],
        )),
        const SizedBox(height: 9),
        ExecutionPipelineCard(snapshot: s),
        const SizedBox(height: 9),
        TradeLearningCard(snapshot: s),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_outlined,
              color: PremiumColors.gold, size: 19),
          title: const Text('Gelişmiş tanılar ve işlem analizi',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          subtitle: const Text('Tek kasa · haber · sinyal öğrenme · API',
              style: TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
          children: [
            ServerRuntimeStatusCard(
                snapshot: s, error: _error, detailed: true),
            const SizedBox(height: 8),
            ServerPaperCard(snapshot: s, loading: _loading,
                error: _error, onRefresh: _refresh,
                onOpenTrades: _showTrades),
          ],
        )),
      ],
    );
  }

  Widget _profit() {
    final s = _snapshot;
    final performance = s?.performance ?? const <String, dynamic>{};
    final growth = s?.pnlTry;
    final positive = (growth ?? 0) >= 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
      children: [
        const PremiumSectionTitle(title: 'Net Performans'),
        const SizedBox(height: 8),
        PremiumSurface(
          gradient: const LinearGradient(
              colors: [Color(0xFF18372E), Color(0xFF111F1C)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BAŞLANGIÇTAN BERİ NET SANAL SONUÇ',
                style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: PremiumColors.gold)),
              const SizedBox(height: 5),
              Text(growth == null ? '—' :
                '${growth >= 0 ? '+' : ''}${formatTry(growth)}',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                    color: positive
                        ? PremiumColors.emerald : PremiumColors.danger)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _stat('Başlangıç',
                  s == null ? '—' : formatTry(s.startingTry))),
                Expanded(child: _stat('Net kasa',
                  s == null ? '—' : formatTry(s.equityTry))),
                Expanded(child: _stat('Masraflar',
                  s == null ? '—' : formatTry(s.feesTry))),
              ]),
              const SizedBox(height: 11),
              Row(children: [
                Expanded(child: _stat('Kapanan',
                    '${performance['closedTrades'] ?? 0}')),
                Expanded(child: _stat('Kazanan',
                    '${performance['wins'] ?? 0}')),
                Expanded(child: _stat('Başarı',
                    performance['winRatePct'] is num
                      ? '${performance['winRatePct']}%' : '—')),
              ]),
              const SizedBox(height: 11),
              Row(children: [
                Expanded(child: _stat('Gözlenen düşüş',
                    performance['drawdownPct'] is num
                    ? '${performance['drawdownPct']}%' : '—')),
                Expanded(child: _stat('Gerçekleşen net',
                    s == null ? '—' : formatTry(s.realizedTry))),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 9),
        TradeLearningCard(snapshot: s),
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: _showTrades,
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: const Text('Tüm sanal işlemleri incele')),
        const SizedBox(height: 9),
        PremiumSurface(child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.show_chart,
              color: PremiumColors.gold, size: 18),
          title: const Text('Kasa eğrisi ve ayrıntılı hesap',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800)),
          children: [
            ServerPaperOverview(
              snapshot: s, loading: _loading, error: _error,
              onOpenBot: () => setState(() => _tab = 2),
              onOpenTrades: _showTrades, onRefresh: _refresh),
          ],
        )),
        const SizedBox(height: 7),
        const Text('Sanal işlemler gerçek para kazancı değildir. '
            'Açık pozisyonlar için kapanış maliyeti tahminidir.',
            style: TextStyle(fontSize: 10,
                color: PremiumColors.muted)),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        color: PremiumColors.muted, fontSize: 10)),
      const SizedBox(height: 4),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_graph_outlined, color: PremiumColors.gold),
          SizedBox(width: 8),
          Text('SanalTrader', style: TextStyle(
            fontWeight: FontWeight.w900, fontSize: 19)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Güncelleme geçmişi', onPressed: _showUpdates,
            icon: const Icon(Icons.history)),
          IconButton(
            tooltip: 'Sunucu verisini yenile', onPressed: _refresh,
            icon: _loading ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh)),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0B1A16), PremiumColors.background,
              Color(0xFF0B1113)])),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: switch (_tab) {
              0 => _panel(),
              1 => _radar(),
              2 => _bot(),
              _ => _profit(),
            },
          ),
        )),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (next) => setState(() => _tab = next),
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet,
              color: PremiumColors.gold), label: 'Kasa'),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar,
              color: PremiumColors.gold), label: 'Radar'),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy,
              color: PremiumColors.gold), label: 'Bot'),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats,
              color: PremiumColors.gold), label: 'Kâr'),
        ],
      ),
    );
  }
}
