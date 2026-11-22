import '../widgets/premium_dashboard.dart';
import 'package:flutter/material.dart';
import '../models/coin_quote.dart';
import '../services/technical_analysis.dart';
import '../widgets/candle_chart.dart';
import '../widgets/mini_chart.dart';
import '../widgets/formatters.dart';

class ExpertAnalysisScreen extends StatelessWidget {
  const ExpertAnalysisScreen({super.key, required this.quote});
  final CoinQuote quote;

  @override
  Widget build(BuildContext context) {
    final report = analyzeTechnical(quote);
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Scaffold(
      appBar: AppBar(title: Text('${quote.symbol} · Teknik analiz')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${quote.name} / TRY', style: textStyle),
          const SizedBox(height: 8),
          Text(formatCoinPriceTry(quote.priceTry),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(report.decisionLabel,
            style: TextStyle(
              color: report.score > .2 ? PremiumColors.emerald
                  : report.score < -.2 ? PremiumColors.danger
                  : Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            )),
          const SizedBox(height: 12),
          if (quote.candles.length >= 4) ...[
            _panel(
              title: 'Saatlik mum grafiği · son 48 tamamlanmış mum',
              child: CandleChart(candles: quote.candles, height: 200),
            ),
            const SizedBox(height: 10),
          ],
          _panel(
            title: 'Fiyat eğilimi',
            child: MiniChart(
              prices: quote.sparkline,
              positive: quote.change24h >= 0,
              height: 120,
            ),
          ),
          const SizedBox(height: 12),
          if (!report.ready)
            const Text('Yeterli geçmiş fiyat yok; teknik yorum oluşturulmadı.',
              style: TextStyle(color: Colors.orangeAccent))
          else ...[
            _panel(title: 'Göstergeler', child: Column(children: [
              _metric('Piyasa eğilimi', report.trendLabel),
              _metric('RSI (14)', report.rsi.toStringAsFixed(1)),
              _metric('EMA20', formatCoinPriceTry(report.ema20)),
              _metric('EMA50', formatCoinPriceTry(report.ema50)),
              _metric('MACD histogramı', report.macdHistogram.toStringAsPrecision(4)),
              _metric('48 saatlik destek', formatCoinPriceTry(report.support)),
              _metric('48 saatlik direnç', formatCoinPriceTry(report.resistance)),
              _metric('24s oynaklık', '%${report.volatility24hPct.toStringAsFixed(1)}'),
              _metric('ATR / fiyat', report.atrPct > 0
                ? '%${report.atrPct.toStringAsFixed(2)}' : 'OHLCV gerekli'),
              _metric('Hacim / 20 saat ort.', report.volumeRatio > 0
                ? '${report.volumeRatio.toStringAsFixed(2)}x' : 'OHLCV gerekli'),
              _metric('Mum yorumu', report.patternLabel),
              _metric('Teknik puan', report.score.toStringAsFixed(2)),
            ])),
            const SizedBox(height: 12),
            _panel(title: 'Bot bunları nasıl yorumluyor?', child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (report.reasons.isEmpty)
                  const Text('Net bir teyit bulunamadı.')
                else
                  for (final reason in report.reasons) _point(reason, Icons.insights),
              ],
            )),
          ],
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _panel(title: 'Dikkat edilmesi gereken riskler', child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in report.warnings)
                  _point(warning, Icons.warning_amber_outlined),
              ],
            )),
          ],
          const SizedBox(height: 14),
          const Text(
            'Gösterge analizi geçmiş kapanış ve varsa tamamlanmış saatlik OHLCV mumlarıyla yapılır. '
            'Döviz dönüşümünde saatlik tarihsel USD/TRY değil güncel USDT/TRY kullanılır. '
            'Bu bir fiyat tahmini garantisi, finansal danışmanlık veya gerçek emir değildir.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) => Card(
    color: PremiumColors.panel,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        child,
      ]),
    ),
  );

  Widget _metric(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(name,
        style: const TextStyle(color: Colors.white70, fontSize: 12))),
      Flexible(child: Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
    ]),
  );

  Widget _point(String text, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: PremiumColors.emerald),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
    ]),
  );
}
