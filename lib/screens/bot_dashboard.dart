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
    this.error,
    this.lastStatus,
  });

  final BotState? state;
  final Map<String, CoinQuote> quotes;
  final Portfolio? wallet;
  final bool busy;
  final ValueChanged<bool> onEnabledChanged;
  final String? error;
  final String? lastStatus;

  @override
  Widget build(BuildContext context) {
    final bot = state;
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
    final equity = wallet?.fullMarketValue(
      quotes.map((id, q) => MapEntry(id, q.priceTry)));
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
        Text('Öğrenen sanal bot', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF192D2C),
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
                Text(error!, style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF19212D),
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
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF19212D),
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
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
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
          color: const Color(0xFF19212D),
          child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _stat('Değerlendirilen tahmin', '${bot?.evaluated ?? 0}')),
                Expanded(child: _stat('Yön doğruluğu', accuracy)),
                Expanded(child: _stat('Bugünkü işlemler', '${bot?.tradesFor(DateTime.now()) ?? 0}/$botMaxTradesPerDay')),
              ]),
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
          Text('${watchlist.length} izleniyor', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        const Text('Sinyaller işlem garantisi değildir; nakit ve risk sınırları ayrıca kontrol edilir.',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 8),
        if (watchlist.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Güncel fiyat bekleniyor. Canlı veya yedek piyasa verisi gelmeden işlem yapılmaz.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else
          for (final coin in watchlist.take(20))
            _signalRow(context, coin, weight),
        if (watchlist.length > 20)
          Text('Diğer ${watchlist.length - 20} coin piyasada izleniyor.',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 10),
        const Text('Risk sınırları', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'İşlem başına en fazla portföyün %12’si, tek coinde %25, toplam coinde %65. Nakit rezervi en az %30. Günlük en fazla 8 emir; aynı coinde 30 dakika bekleme. Yaklaşık -%6 zarar koruması ve +%8 kâr hedefi (garanti değil).',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 5),
        Text('650 TL başlangıç bakiyesinde tek alışın üst sınırı yaklaşık ${formatTry(650 * botMaxOrderShare)}.',
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 16),
        const Text('Botun işlem günlüğü', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (bot == null || bot.activities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: Text('Bot henüz sanal işlem yapmadı.', style: TextStyle(color: Colors.white54))),
          )
        else
          for (final event in bot.activities)
            Card(color: const Color(0xFF19212D), child: ListTile(
              dense: true,
              title: Text(event.message, style: const TextStyle(fontSize: 12)),
              subtitle: Text('${event.at.toLocal().day}.${event.at.toLocal().month} · '
                '${event.at.toLocal().hour.toString().padLeft(2, '0')}:'
                '${event.at.toLocal().minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            )),
        const SizedBox(height: 14),
        const Text('Not: Bu site kapanınca bot durur; yeniden açıldığında yalnızca yeni fiyatlardan devam eder. Fiyat sağlayıcısı hata verirse işlem yapılmaz. Portföy ile bot verileri bu tarayıcıda saklanır.',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _signalRow(BuildContext context, CoinQuote quote, List<double> weights) {
    final learningScore = botScore(quote, weights);
    final analysis = analyzeTechnical(quote);
    final positive = analysis.ready && analysis.score >= .35 &&
        learningScore >= botBuyThreshold;
    final danger = analysis.ready && analysis.score <= -.35;
    final color = positive ? const Color(0xFF43D9A3) :
      danger ? const Color(0xFFF27777) : Colors.white54;
    final label = !analysis.ready ? 'VERİ YOK' :
        positive ? 'ALIM ADAYI' : danger ? 'SATIŞ BASKISI' : 'BEKLE';
    return Card(
      color: const Color(0xFF19212D),
      margin: const EdgeInsets.only(bottom: 5),
      child: ExpansionTile(
        dense: true,
        title: Text('${quote.symbol} · ${formatCoinPriceTry(quote.priceTry)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text('${analysis.trendLabel} · RSI ${analysis.rsi.toStringAsFixed(0)}'
          ' · Teknik ${analysis.score.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              for (final reason in analysis.reasons.take(3))
                Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $reason', style: const TextStyle(fontSize: 11))),
              for (final warning in analysis.warnings.take(2))
                Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('⚠ $warning',
                    style: const TextStyle(fontSize: 11, color: Colors.orangeAccent))),
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
      Text(name, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    ],
  );
}
