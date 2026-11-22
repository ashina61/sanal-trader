import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_paper_repository.dart';
import '../widgets/server_paper_card.dart';
import '../widgets/server_paper_overview.dart';
import '../widgets/premium_dashboard.dart';
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        ServerPaperOverview(
          snapshot: s, loading: _loading, error: _error,
          onOpenBot: () => setState(() => _tab = 2),
          onOpenTrades: _showTrades, onRefresh: _refresh,
        ),
        const SizedBox(height: 14),
        ServerPaperPositionsPanel(
          snapshot: s, onOpenTrades: _showTrades),
        const SizedBox(height: 14),
        PremiumSurface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SON OTONOM KARAR', style: TextStyle(
                color: PremiumColors.gold,
                fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text(plan['reason']?.toString() ??
                  'Bot piyasa analizini henüz kaydetmedi.',
                style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _stat('Piyasa yönü',
                  plan['marketRegime']?.toString() ?? '—')),
                Expanded(child: _stat('Son işlem',
                  s?.trades.isNotEmpty == true
                    ? s!.trades.first['symbol']?.toString() ?? '—' : '—')),
              ]),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => setState(() => _tab = 2),
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('Karar ayrıntıları'),
              ),
            ],
          ),
        ),
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
    final rejectionMap = rejected is Map ? rejected : const {};
    final blocked = plan['action']?.toString() == 'WAIT';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        const PremiumSectionTitle(title: 'Botun Fırsat Radarı'),
        const SizedBox(height: 8),
        const Text('Bu adaylar yalnızca arka plan botunun incelediği '
          'gerçek fiyatlardan gelir. Ekranda alım veya satım butonu yok.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
        const SizedBox(height: 13),
        PremiumSurface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _stat('Likidite taraması',
                  '${plan['universe'] ?? s?.tracked ?? '—'} coin')),
                Expanded(child: _stat('Saatlik grafik',
                  '${plan['historyPairs'] ?? '—'}')),
                Expanded(child: _stat('15 dk grafik',
                  '${plan['intradayPairs'] ?? '—'}')),
              ]),
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: _stat('Günlük emir',
                  '${plan['todayOrders'] ?? '—'}/${plan['dailyLimit'] ?? 16}')),
                Expanded(child: _stat('Ana trend',
                  plan['marketRegime']?.toString() ?? '—')),
              ]),
              if (blocked) ...[
                const SizedBox(height: 12),
                Text('BEKLE · ${plan['reason'] ?? 'Veri veya risk teyidi gerekiyor'}',
                  style: const TextStyle(
                    color: PremiumColors.gold, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 17),
        const PremiumSectionTitle(title: 'Doğrulanmış teknik adaylar'),
        const SizedBox(height: 9),
        if (candidates.isEmpty)
          const PremiumSurface(child: Text(
            'Şu anda yeni işlem için uygun doğrulanmış aday yok. '
            'Bot, risk uygun değilse emir açmaz.',
            style: TextStyle(color: PremiumColors.muted, fontSize: 12))),
        for (final item in candidates)
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: PremiumSurface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.insights_outlined,
                      color: PremiumColors.gold, size: 19),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      item['symbol']?.toString() ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(item['action']?.toString() ?? '—',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PremiumColors.emerald)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _stat('Sinyal puanı',
                      item['score']?.toString() ?? '—')),
                    Expanded(child: _stat('6s momentum',
                      item['momentum6Pct'] == null ? '—'
                        : '${item['momentum6Pct']}%')),
                    Expanded(child: _stat('1s momentum',
                      item['momentum1hPct'] == null ? '—'
                        : '${item['momentum1hPct']}%')),
                  ]),
                ],
              ),
            ),
          ),
        if (rejectionMap.isNotEmpty) ...[
          const SizedBox(height: 16),
          const PremiumSectionTitle(title: 'Neden işlem açılmadı?'),
          const SizedBox(height: 7),
          PremiumSurface(
            child: Column(children: [
              for (final item in rejectionMap.entries.take(8))
                Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text(item.key.toString(),
                      style: const TextStyle(fontSize: 11))),
                    Text('${item.value} coin',
                      style: const TextStyle(fontSize: 11,
                        color: PremiumColors.muted)),
                  ]),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _bot() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
    children: [
      ServerPaperCard(snapshot: _snapshot, loading: _loading,
        error: _error, onRefresh: _refresh,
        onOpenTrades: _showTrades),
      const SizedBox(height: 14),
      const PremiumSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BOTUN TEK HEDEFİ',
              style: TextStyle(color: PremiumColors.gold,
                fontWeight: FontWeight.w800, fontSize: 11)),
            SizedBox(height: 8),
            Text('650 TL sanal kasayı komisyon sonrası net olarak '
              'büyütmeye çalışmak. Aynı anda riski sınırlamak, '
              'gerçek kapanmış işlemlerden öğrenmek ve '
              'avantaj olmayan piyasada beklemek.'),
            SizedBox(height: 7),
            Text('Telefon kapalıyken hesaplamaları sunucu yapar. '
              'Sürekli kâr ya da her döngüde işlem garantisi yoktur.',
              style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
          ]),
      ),
    ],
  );

  Widget _profit() {
    final s = _snapshot;
    final performance = s?.performance ?? const <String, dynamic>{};
    final growth = s == null ? null : s.pnlTry;
    final positive = (growth ?? 0) >= 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        const PremiumSectionTitle(title: 'Tek Kasa · Performans'),
        const SizedBox(height: 10),
        ServerPaperOverview(
          snapshot: s, loading: _loading, error: _error,
          onOpenBot: () => setState(() => _tab = 2),
          onOpenTrades: _showTrades, onRefresh: _refresh,
        ),
        const SizedBox(height: 14),
        PremiumSurface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gerçek sanal net sonuç',
                style: const TextStyle(color: PremiumColors.muted)),
              const SizedBox(height: 7),
              Text(s == null ? '—' :
                  '${growth! >= 0 ? '+' : ''}${formatTry(growth)}',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900,
                  color: positive ? PremiumColors.emerald : PremiumColors.danger)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _stat('Başlangıç',
                  s == null ? '—' : formatTry(s.startingTry))),
                Expanded(child: _stat('Ücretler',
                  s == null ? '—' : formatTry(s.feesTry))),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _stat('Kapanan işlem',
                  '${performance['closedTrades'] ?? 0}')),
                Expanded(child: _stat('Kazanan',
                  '${performance['wins'] ?? 0}')),
                Expanded(child: _stat('Kazanma oranı',
                  performance['winRatePct'] is num
                  ? '${performance['winRatePct']}%' : 'Henüz ölçülmedi')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _stat('Gözlenen gerileme',
                  performance['drawdownPct'] is num
                  ? '${performance['drawdownPct']}%' : '—')),
                Expanded(child: _stat('Açık LONG/SHORT',
                  '${s == null ? '—' : s.holdings.length + s.shorts.length}')),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _showTrades,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Bütün sanal işlem geçmişi')),
        const SizedBox(height: 7),
        const Text('Tüm rakamlar aynı sunucu sanal kasasından gelir; '
          'varsayımsal test kârları bu toplamda yoktur.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        color: PremiumColors.muted, fontSize: 10)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w800)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
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
        height: 65,
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
