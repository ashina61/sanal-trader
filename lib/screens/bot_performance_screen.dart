import 'package:flutter/material.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/learning_bot.dart';
import '../widgets/formatters.dart';
import '../widgets/premium_dashboard.dart';
import '../services/server_paper_repository.dart';
import '../widgets/server_paper_card.dart';

/// Distinguishes *realized* virtual-trade performance from predictive accuracy.
class BotPerformanceScreen extends StatelessWidget {
  const BotPerformanceScreen({
    super.key,
    required this.wallet,
    required this.quotes,
    required this.bot,
    required this.onViewTrades,
    required this.serverSnapshot,
    required this.serverBusy,
    required this.serverError,
    required this.onViewServerTrades,
  });
  final Portfolio? wallet;
  final Map<String, CoinQuote> quotes;
  final BotState? bot;
  final VoidCallback onViewTrades;
  final ServerPaperSnapshot? serverSnapshot;
  final bool serverBusy;
  final String? serverError;
  final VoidCallback onViewServerTrades;

  @override
  Widget build(BuildContext context) {
    final ledger = bot?.profitLearning;
    final bt = bot?.backtest;
    final equity = wallet?.fullMarketValue(
      quotes.map((id, q) => MapEntry(id, q.priceTry)));
    final pnl = equity == null ? null : equity - initialCashTry;
    final botWin = ledger?.winRate;
    final top = ledger?.perCoin.entries.toList() ?? [];
    top.sort((a, b) => b.value.realizedTry.compareTo(a.value.realizedTry));
    final peak = bot?.peakEquityTry ?? initialCashTry;
    final dd = equity == null ? null
        : (1 - equity / peak).clamp(0.0, 1.0);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const PremiumSectionTitle(title: 'Performans Merkezi'),
        const SizedBox(height: 6),
        const Text(
          'Gerçek para değil; yalnızca tamamlanan sanal emirler ve '
          'güncel piyasa fiyatı ile hesaplanan sonuçlar.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 12)),
        const SizedBox(height: 14),
        const PremiumSectionTitle(title: 'Sunucu Botu · Gerçek Sanal Test Sonuçları'),
        const SizedBox(height: 9),
        ServerPaperSummaryTile(
          snapshot: serverSnapshot,
          loading: serverBusy,
          error: serverError,
          onTap: onViewServerTrades,
        ),
        const SizedBox(height: 10),
        if (serverSnapshot != null)
          PremiumSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: _metric('Sunucu net kapanmış kâr',
                    formatTry(serverSnapshot!.realizedTry))),
                  Expanded(child: _metric('Sunucu toplam değişimi',
                    formatTry(serverSnapshot!.pnlTry))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _metric('LONG pozisyon',
                    '${serverSnapshot!.holdings.length}')),
                  Expanded(child: _metric('SHORT pozisyon',
                    '${serverSnapshot!.shorts.length}')),
                ]),
                const SizedBox(height: 9),
                const Text('Bu sunucu sonuçları aşağıdaki yerel bot '
                    'istatistiklerine EKLENMEZ. Ayrı sanal hesaplardır.',
                  style: TextStyle(color: PremiumColors.muted,
                    fontSize: 11)),
                TextButton.icon(
                  onPressed: onViewServerTrades,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Sunucu işlem geçmişi'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const PremiumSectionTitle(title: 'Yerel / Tarayıcı Botunun Sonuçları'),
        const SizedBox(height: 10),
        PremiumSurface(
          gradient: const LinearGradient(colors: [
            Color(0xFF133E33), Color(0xFF101D1A),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('SANAL PORTFÖY',
              style: TextStyle(color: PremiumColors.gold,
                fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(equity == null ? 'Güncel fiyat bekleniyor' : formatTry(equity),
              style: const TextStyle(fontSize: 28,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 13),
            Row(children: [
              Expanded(child: _metric('Toplam getiri',
                pnl == null ? '—' : formatTry(pnl))),
              Expanded(child: _metric('Zirveden düşüş',
                dd == null ? '—' : '%${(dd * 100).toStringAsFixed(1)}')),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        PremiumSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Text('BOT İŞLEM SONUÇLARI',
            style: TextStyle(color: PremiumColors.gold, fontSize: 11,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Net gerçekleşen bot kârı',
              formatTry(ledger?.realizedTry ?? 0))),
            Expanded(child: _metric('Kazanma oranı',
              botWin == null ? 'Henüz yok'
                : '%${(100 * botWin).toStringAsFixed(1)}')),
          ]),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: _metric('Kapanan bot satışları',
              '${ledger?.closedTrades ?? 0}')),
            Expanded(child: _metric('Ödenen sanal komisyon',
              formatTry(ledger?.totalBotFeesTry ?? 0))),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Net sonuç alış/satış komisyonlarını içerir. '
            'Açık pozisyon kârı henüz gerçekleşmiş sonuç sayılmaz. '
            'Sadece bot tarafından yapılan emirler bu tabloda yer alır.',
            style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
        ])),
        const SizedBox(height: 16),
        PremiumSurface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('EĞİTİM DIŞI 24 SAAT · KÂRLILIK DENEMESİ',
              style: TextStyle(color: PremiumColors.gold, fontSize: 11,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (bt == null)
              const Text('Yeterli saatlik fiyat geçmişi ve bot eğitimi bekleniyor.',
                style: TextStyle(color: PremiumColors.muted, fontSize: 12))
            else ...[
              Row(children: [
                Expanded(child: _metric('Simülasyon getirisi',
                  '%${bt.strategyReturnPct.toStringAsFixed(2)}')),
                Expanded(child: _metric('Aynı dönemde al-tut',
                  '%${bt.buyHoldReturnPct.toStringAsFixed(2)}')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _metric('Test işlemleri',
                  '${bt.closedTrades}')),
                Expanded(child: _metric('En kötü geri çekilme',
                  '%${bt.maxDrawdownPct.toStringAsFixed(1)}')),
              ]),
            ],
            const SizedBox(height: 9),
            const Text('Bu rakamlar geçmiş verilere uygulanmış varsayımsal '
              'emirlerin net sonuçlarıdır; 650 TL kasaya işlenmez. '
              'Maliyetler %0,1 komisyon + %0,05 kayma / emir yönü.',
              style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
          ]),
        ),
        const SizedBox(height: 17),
        PremiumSectionTitle(
          title: 'Coin Bazında Öğrenme',
          trailing: Text('${top.length} coin',
            style: const TextStyle(
              color: PremiumColors.muted, fontSize: 12))),
        const SizedBox(height: 9),
        if (top.isEmpty)
          const PremiumSurface(
            child: Text('Bot henüz sanal satış kapatmadı. '
                'Performans bilgisi gerçek işlem sonuçları geldikçe oluşacak.',
              style: TextStyle(color: PremiumColors.muted)),
          )
        else for (final entry in top.take(25))
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: PremiumSurface(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quotes[entry.key]?.symbol ?? entry.key.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${entry.value.closed} kapalı satış · '
                      '${(100 * entry.value.winRate).toStringAsFixed(0)}% başarılı',
                      style: const TextStyle(
                        color: PremiumColors.muted, fontSize: 11)),
                  ])),
                Text(formatTry(entry.value.realizedTry),
                  style: TextStyle(
                    color: entry.value.realizedTry >= 0
                        ? PremiumColors.emerald : PremiumColors.danger,
                    fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onViewTrades,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Tüm sanal işlem geçmişini aç'),
        ),
        const SizedBox(height: 12),
        const Text('Öğrenme kâr garantisi değildir. '
          'Sınırlı örneklemdeki başarı, başka piyasa koşullarında '
          'tekrarlanmayabilir. Tarayıcı kapalıyken bot çalışmaz.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
      ],
    );
  }

  Widget _metric(String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(
        color: PremiumColors.muted, fontSize: 11)),
      const SizedBox(height: 5),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800))),
    ],
  );
}
