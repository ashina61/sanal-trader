import '../widgets/premium_dashboard.dart';
import 'package:flutter/material.dart';
import '../services/learning_bot.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/technical_analysis.dart';
import 'expert_analysis_screen.dart';
import '../widgets/formatters.dart';

class BotDashboard extends StatelessWidget {
  const BotDashboard({
    super.key,
    required this.state,
    required this.quotes,
    required this.wallet,
    required this.busy,
    required this.onEnabledChanged,
    this.onOpenPerformance,
    this.onRetrain,
    this.serverBotCard,
    this.error,
    this.lastStatus,
  });

  final BotState? state;
  final Map<String, CoinQuote> quotes;
  final Portfolio? wallet;
  final bool busy;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback? onOpenPerformance;
  final VoidCallback? onRetrain;
  final Widget? serverBotCard;
  final String? error;
  final String? lastStatus;

  @override
  Widget build(BuildContext context) {
    final bot = state;
    final bt = bot?.backtest;
    final active = bot?.enabled ?? false;
    final weight = bot?.weights ?? const [1 / 3, 1 / 3, 1 / 3];
    final accuracy = (bot?.evaluated ?? 0) == 0 ? 'Henüz ölçülmedi' :
      '%'+ (100 * bot!.correct / bot.evaluated).toStringAsFixed(1);
    final watchlist = quotes.values.where((q) => q.isFresh).toList()
      ..sort((a, b) => botScore(b, weight).compareTo(botScore(a, weight)));
    final trained = bot != null && bot.trainingVersion > 0;
    final holdout = trained && bot.holdoutExamples > 0
      ? '%${(100 * bot.holdoutCorrect / bot.holdoutExamples).toStringAsFixed(1)}'
      : 'Henüz yok';
    final baseline = trained && bot.holdoutExamples > 0
      ? '%${(100 * bot.baselineCorrect / bot.holdoutExamples).toStringAsFixed(1)}'
      : '—';
    final equity = wallet?.fullMarketValue({
      for (final q in quotes.values)
        if (q.isFresh) q.id: q.priceTry,
    });
    final peak = bot?.peakEquityTry ?? initialCashTry;
    final drawdown = equity == null || peak <= 0 ? null :
      (1 - equity / peak).clamp(0.0, 1.0);
    final benchmark = quotes['bitcoin'];
    final market = benchmark == null ? TechnicalReport.insufficient
      : analyzeTechnical(benchmark);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        if (serverBotCard != null) ...[
          serverBotCard!,
          const SizedBox(height: 18),
        ],
        Card(
          color: PremiumColors.panel,
          child: ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Gelişmiş · yerel deneme botu',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            subtitle: const Text('Ana sunucu botunu etkilemez',
              style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
            childrenPadding: const EdgeInsets.all(12),
            children: [
        Text('Yerel Bot · Yalnızca Tarayıcı Açıkken', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          color: PremiumColors.panelRaised,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(active ? 'Bot çalışıyor' : 'Bot kapalı', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Yalnızca sanal işlemler • Tarayıcı açıkken'),
                value: active,
                onChanged: bot == null || busy ? null : onEnabledChanged,
              ),
              const Divider(),
              Text(
                active
                    ? (busy ? 'Piyasa inceleniyor...' : (lastStatus ?? 'Yeni veriler bekleniyor.'))
                    : 'Bot durduruldu. İstediğin zaman yeniden başlatabilirsin.',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12, color: PremiumColors.gold)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (onRetrain != null)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: busy || bot == null ? null : onRetrain,
              icon: const Icon(Icons.model_training_outlined),
              label: const Text('Geçmiş veriden yeniden eğit'),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          color: PremiumColors.panel,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Gerçekleşmiş sanal işlemden öğrenme',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _stat('Bot net kapanmış kârı',
                  formatTry(bot?.profitLearning.realizedTry ?? 0))),
                Expanded(child: _stat('Kapanan sanal satış',
                  '${bot?.profitLearning.closedTrades ?? 0}')),
                Expanded(child: _stat('Kazanan işlem',
                  bot?.profitLearning.winRate == null ? 'Yok'
                    : '%${(100 * bot!.profitLearning.winRate!).toStringAsFixed(0)}')),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Bot yalnızca gerçekleşen sanal satışlardan, '
                'komisyon sonrası net sonucu öğrenir.',
                style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
              if (onOpenPerformance != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child:
                  TextButton.icon(
                    onPressed: onOpenPerformance,
                    icon: const Icon(Icons.query_stats, size: 17),
                    label: const Text('Performans merkezini aç'),
                  )),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: PremiumColors.panel,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Geçmiş veriden eğitim', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(trained
                ? '${bot.trainedCoins} coin · ${bot.trainingExamples} geçmiş eğitim örneği'
                : 'Geçmiş veriler toplanıyor; eğitimsiz bot alış emri açmaz.',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _stat('Ayrılmış 24s test', holdout)),
                Expanded(child: _stat('Basit momentum', baseline)),
                Expanded(child: _stat('Test örneği', '${bot?.holdoutExamples ?? 0}')),
              ]),
              const SizedBox(height: 6),
              const Text('Bu oranlar yön tahmini içindir; komisyon sonrası kâr veya gelecekteki başarı değildir.',
                style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: PremiumColors.panel,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Komisyonlu ileri-test · son 24 saat',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                const Icon(Icons.fact_check_outlined, color: PremiumColors.gold, size: 20),
              ]),
              const SizedBox(height: 6),
              const Text('Eğitim dışında kalan fiyatlarla geriye dönük deney. '
                'Gerçek sanal cüzdan işlemi değildir.',
                style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
              const SizedBox(height: 12),
              if (bt == null)
                const Text('Eğitim tamamlandığında test hesaplanır.',
                  style: TextStyle(color: PremiumColors.muted))
              else ...[
                Row(children: [
                  Expanded(child: _stat('Strateji getirisi',
                    '%${bt.strategyReturnPct.toStringAsFixed(2)}')),
                  Expanded(child: _stat('Al-tut karşılığı',
                    '%${bt.buyHoldReturnPct.toStringAsFixed(2)}')),
                  Expanded(child: _stat('Maks. gerileme',
                    '%${bt.maxDrawdownPct.toStringAsFixed(1)}')),
                ]),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(child: _stat('İncelenen coin',
                    '${bt.coins}')),
                  Expanded(child: _stat('Kapanan test işlemi',
                    '${bt.closedTrades}')),
                  Expanded(child: _stat('Test kazanma oranı',
                    bt.winRate == null ? 'İşlem yok'
                      : '%${(bt.winRate! * 100).toStringAsFixed(1)}')),
                ]),
              ],
              const SizedBox(height: 10),
              const Text('Varsayımsal maliyet: her alış ve satışta %0,1 işlem '
                'ücreti + %0,05 fiyat kayması. Yalnızca geçmiş sonuç; '
                'gelecek getiriyi göstermez.',
                style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: PremiumColors.panel,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Piyasa rejimi ve risk', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _stat('BTC piyasa göstergesi',
                market.ready ? market.trendLabel : 'Geçmiş verisi yok'),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _stat('Portföy zirvesi', formatTry(peak))),
                Expanded(child: _stat('Zirveden gerileme',
                  drawdown == null ? '—' : '%${(drawdown * 100).toStringAsFixed(1)}')),
              ]),
              if (drawdown != null && drawdown >= .12)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Risk freni: yeni sanal alışlar durduruldu. Mevcut varlıklar için satış kontrolü devam eder.',
                    style: TextStyle(color: PremiumColors.gold, fontSize: 12)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Nasıl öğreniyor?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'Geçmiş saatlik fiyatlardan üç stratejiyi eğitir. Son 24 saati eğitime katmadan ayrı test eder. Daha sonra canlı fiyat geldiğinde 15 dakikadan eski tahminleri gerçek hareketlerle karşılaştırır. Bu sistem bir dil modeli değildir ve başarı garantisi yoktur.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Card(
          color: PremiumColors.panel,
          child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _stat('Değerlendirilen tahmin', '${bot?.evaluated ?? 0}')),
                Expanded(child: _stat('Yön doğruluğu', accuracy)),
                Expanded(child: _stat('Bugünkü işlemler', '${bot?.tradesFor(DateTime.now()) ?? 0}/$botMaxTradesPerDay')),
              ]),
              const SizedBox(height: 15),
              const Divider(),
              const Text('Teknik analize duyulan güven (canlı öğrenme)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _stat('Teknik ağırlık',
                  '%${((bot?.technicalWeight ?? .35) * 100).toStringAsFixed(1)}')),
                Expanded(child: _stat('Teknik yön doğruluğu',
                  (bot?.technicalEvaluated ?? 0) == 0 ? 'Veri bekliyor' :
                    '%${(100 * (bot!.technicalCorrect / bot.technicalEvaluated)).toStringAsFixed(1)}')),
                Expanded(child: _stat('Test edilen sinyal',
                  '${bot?.technicalEvaluated ?? 0}')),
              ]),
              const SizedBox(height: 7),
              const Text('Ağırlık, sonraki gerçek fiyatla karşılaştırılan teknik yön tahminlerine göre yavaş güncellenir.',
                style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
              const SizedBox(height: 16),
              const Text('Öğrenilen strateji ağırlıkları', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++) ...[
                Row(children: [
                  Expanded(child: Text(botExpertLabels[i], style: const TextStyle(fontSize: 12))),
                  Text('%${(100 * weight[i]).toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: weight[i], minHeight: 5, borderRadius: BorderRadius.circular(12)),
                const SizedBox(height: 11),
              ],
            ],
          )),
        ),

        const SizedBox(height: 10),
        Row(children: [
          const Text('Canlı bot sinyalleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${watchlist.length} izleniyor', style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        const Text('Sinyaller işlem garantisi değildir; nakit ve risk sınırları ayrıca kontrol edilir.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
        const SizedBox(height: 8),
        if (watchlist.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Güncel fiyat bekleniyor. Canlı veya yedek piyasa verisi gelmeden işlem yapılmaz.',
              style: TextStyle(color: PremiumColors.muted, fontSize: 12)),
          )
        else
          for (final coin in watchlist.take(20))
            _signalRow(context, coin, weight),
        if (watchlist.length > 20)
          Text('Diğer ${watchlist.length - 20} coin piyasada izleniyor.',
            style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
        const SizedBox(height: 10),
        const Text('Risk sınırları', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'İşlem başına en fazla portföyün %12’si, tek coinde %25, toplam coinde %65. Nakit rezervi en az %30. Günlük en fazla 8 emir; aynı coinde 30 dakika bekleme. Yaklaşık -%6 zarar koruması ve +%8 kâr hedefi (garanti değil).',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 5),
        Text('650 TL başlangıç bakiyesinde tek alışın üst sınırı yaklaşık ${formatTry(650 * botMaxOrderShare)}.',
          style: const TextStyle(fontSize: 12, color: PremiumColors.muted)),
        const SizedBox(height: 16),
        const Text('Botun işlem günlüğü', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (bot == null || bot.activities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: Text('Bot henüz sanal işlem yapmadı.', style: TextStyle(color: PremiumColors.muted))),
          )
        else
          for (final event in bot.activities)
            Card(color: PremiumColors.panel, child: ListTile(
              dense: true,
              title: Text(event.message, style: const TextStyle(fontSize: 12)),
              subtitle: Text('${event.at.toLocal().day}.${event.at.toLocal().month} · '
                '${event.at.toLocal().hour.toString().padLeft(2, '0')}:'
                '${event.at.toLocal().minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11, color: PremiumColors.muted)),
            )),
        const SizedBox(height: 14),
        const Text('Bu eski yerel bot yalnızca tarayıcı açıkken çalışır. '
          'Ana sunucu botu ve ana kasa etkilenmez.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signalRow(BuildContext context, CoinQuote quote, List<double> weights) {
    final learningScore = botScore(quote, weights);
    final analysis = analyzeTechnical(quote);
    final positive = analysis.ready && analysis.score >= .35 &&
        learningScore >= botBuyThreshold;
    final danger = analysis.ready && analysis.score <= -.35;
    final color = positive ? PremiumColors.emerald :
      danger ? PremiumColors.danger : Colors.white54;
    final label = !analysis.ready ? 'VERİ YOK' :
        positive ? 'ALIM ADAYI' : danger ? 'SATIŞ BASKISI' : 'BEKLE';
    return Card(
      color: PremiumColors.panel,
      margin: const EdgeInsets.only(bottom: 5),
      child: ExpansionTile(
        dense: true,
        title: Text('${quote.symbol} · ${formatCoinPriceTry(quote.priceTry)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text('${analysis.trendLabel} · RSI ${analysis.rsi.toStringAsFixed(0)}'
          ' · Teknik ${analysis.score.toStringAsFixed(2)}',
          style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
        trailing: Text(label, style: TextStyle(color: color,
          fontWeight: FontWeight.w700, fontSize: 10)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Öğrenen strateji: ${learningScore.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              if (!analysis.ready) const Text(
                'Kapanış geçmişi olmadan teknik işlem önerisi yapılmaz.',
                style: TextStyle(fontSize: 11, color: PremiumColors.muted),
              ),
              for (final reason in analysis.reasons.take(3))
                Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $reason', style: const TextStyle(fontSize: 11))),
              for (final warning in analysis.warnings.take(2))
                Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('⚠ $warning',
                    style: const TextStyle(fontSize: 11, color: PremiumColors.gold))),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => ExpertAnalysisScreen(quote: quote),
                  )),
                  icon: const Icon(Icons.query_stats, size: 16),
                  label: const Text('Detaylı teknik analiz'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stat(String name, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontSize: 10, color: PremiumColors.muted)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    ],
  );
}
