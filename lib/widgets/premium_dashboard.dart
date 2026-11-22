import 'package:flutter/material.dart';

import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/learning_bot.dart';
import '../services/technical_analysis.dart';
import 'formatters.dart';
import 'mini_chart.dart';

/// Consistent luxury fintech palette. Purely visual: no imaginary prices.
abstract final class PremiumColors {
  static const background = Color(0xFF07110F);
  static const panel = Color(0xFF111F1C);
  static const panelRaised = Color(0xFF172623);
  static const emerald = Color(0xFF44E5AB);
  static const emeraldDim = Color(0xFF13392E);
  static const gold = Color(0xFFE9C47A);
  static const goldDim = Color(0xFF3B3120);
  static const danger = Color(0xFFFF796F);
  static const muted = Color(0xFF99ABA5);
  static const border = Color(0xFF29433A);
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradient,
    this.borderColor,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: PremiumColors.panel,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? PremiumColors.border.withValues(alpha: .85)),
          boxShadow: const [
            BoxShadow(color: Color(0x26000000), blurRadius: 22, offset: Offset(0, 12)),
          ],
        ),
        child: child,
      );
}

class PremiumSectionTitle extends StatelessWidget {
  const PremiumSectionTitle({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 3,
            height: 19,
            decoration: BoxDecoration(
              color: PremiumColors.gold,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ],
      );
}

class PremiumPortfolioCard extends StatelessWidget {
  const PremiumPortfolioCard({
    super.key,
    required this.wallet,
    required this.quotes,
    required this.cloudMode,
  });

  final Portfolio? wallet;
  final Map<String, CoinQuote> quotes;
  final bool cloudMode;

  @override
  Widget build(BuildContext context) {
    final total = wallet?.fullMarketValue(quotes.map(
      (id, coin) => MapEntry(id, coin.priceTry)));
    final pnl = total == null ? null : total - initialCashTry;
    final percent = pnl == null ? null : 100 * pnl / initialCashTry;
    final up = (pnl ?? 0) >= 0;
    final btc = quotes['bitcoin'];
    final hasBtcChart = btc != null && btc.sparkline.length > 1;
    return PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF114337), Color(0xFF122821), Color(0xFF101B19)],
      ),
      borderColor: const Color(0xFF3A7662),
      radius: 25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('YEREL SANAL PORTFÖY',
              style: TextStyle(color: Color(0xFFCADDD4), fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.05))),
            const Icon(Icons.verified_user_outlined,
              color: PremiumColors.gold, size: 16),
            const SizedBox(width: 5),
            Text(cloudMode ? 'FIREBASE DEMO' : 'YEREL DEMO',
              style: const TextStyle(color: PremiumColors.gold, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: .5)),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final canShowChart = hasBtcChart && constraints.maxWidth > 320;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(total == null
                            ? wallet == null ? 'Yükleniyor...' : 'Fiyat bekleniyor'
                            : formatTry(total),
                          style: const TextStyle(fontSize: 29,
                            fontWeight: FontWeight.w900, letterSpacing: -.8)),
                      ),
                      const SizedBox(height: 9),
                      if (pnl == null)
                        const Text('Değerleme için güncel fiyat bekleniyor',
                          style: TextStyle(fontSize: 11, color: PremiumColors.muted))
                      else
                        Row(children: [
                          Icon(up ? Icons.trending_up : Icons.trending_down,
                            size: 16, color: up ? PremiumColors.emerald : PremiumColors.danger),
                          const SizedBox(width: 5),
                          Flexible(child: Text(
                            '${up ? '+' : ''}${formatTry(pnl)} · ${formatChange(percent!)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12,
                              color: up ? PremiumColors.emerald : PremiumColors.danger))),
                        ]),
                    ],
                  ),
                ),
                if (canShowChart) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: constraints.maxWidth * .32,
                    child: Column(children: [
                      const Text('BTC · 7g eğilim',
                        style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
                      const SizedBox(height: 3),
                      MiniChart(
                        prices: btc.sparkline, positive: btc.change24h >= 0, height: 54),
                    ]),
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: .12)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _stat(Icons.account_balance_wallet_outlined,
              'Sanal nakit', wallet == null ? '—' : formatTry(wallet!.cashTry))),
            const SizedBox(width: 7),
            Expanded(child: _stat(Icons.show_chart, 'Net kâr/zarar',
              pnl == null ? '—' : formatTry(pnl),
              color: pnl == null ? null : up ? PremiumColors.emerald : PremiumColors.danger)),
            const SizedBox(width: 7),
            Expanded(child: _stat(Icons.percent, 'Toplam getiri',
              percent == null ? '—' : formatChange(percent),
              color: percent == null ? null : up ? PremiumColors.emerald : PremiumColors.danger)),
          ]),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String name, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: PremiumColors.gold, size: 13),
            const SizedBox(width: 5),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PremiumColors.muted, fontSize: 10))),
          ]),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
              style: TextStyle(color: color ?? Colors.white,
                fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      );
}

class PremiumMarketTile extends StatelessWidget {
  const PremiumMarketTile({super.key, required this.quote, required this.onTap});
  final CoinQuote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final up = quote.change24h >= 0;
    final color = up ? PremiumColors.emerald : PremiumColors.danger;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFF253C36),
              child: Text(quote.symbol.isEmpty ? '?' : quote.symbol[0],
                style: const TextStyle(color: PremiumColors.gold,
                  fontWeight: FontWeight.w900, fontSize: 17)),
            ),
            const SizedBox(width: 11),
            Expanded(flex: 3, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quote.symbol, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text(quote.volume24hUsdt >= 1000000
                    ? '${(quote.volume24hUsdt / 1000000).toStringAsFixed(0)}M USDT hacim'
                    : quote.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PremiumColors.muted, fontSize: 10)),
              ],
            )),
            Expanded(flex: 2, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: MiniChart(
                prices: quote.sparkline,
                positive: up,
                height: 31,
              ),
            )),
            Expanded(flex: 3, child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
                  child: Text(formatCoinPriceTry(quote.priceTry),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(formatChange(quote.change24h),
                    style: TextStyle(fontSize: 10, color: color,
                      fontWeight: FontWeight.w800)),
                ),
              ],
            )),
            const SizedBox(width: 3),
          ]),
        ),
      ),
    );
  }
}

class PremiumBotOverview extends StatelessWidget {
  const PremiumBotOverview({
    super.key,
    required this.bot,
    required this.btc,
    required this.onTap,
  });

  final BotState? bot;
  final CoinQuote? btc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final report = btc == null
        ? TechnicalReport.insufficient : analyzeTechnical(btc!);
    final active = bot?.enabled == true;
    final count = bot?.technicalEvaluated ?? 0;
    final correct = bot?.technicalCorrect ?? 0;
    final reliability = count == 0 ? null : correct / count;
    final risk = !report.ready ? 'Belirsiz'
        : report.riskElevated ? 'Yüksek' : 'Kontrollü';
    return PremiumSurface(
      gradient: const LinearGradient(
        colors: [Color(0xFF14392F), Color(0xFF111D1B), Color(0xFF171D1A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderColor: const Color(0xFF53745B),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                Color(0xFF275A49), Color(0xFF0C201D),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PremiumColors.gold.withValues(alpha: .5)),
            ),
            child: const Icon(Icons.smart_toy_outlined,
              size: 28, color: PremiumColors.gold),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yerel Uzman Bot', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900)),
              Text('Öğrenen sanal işlem asistanı',
                style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: active
                ? PremiumColors.emerald.withValues(alpha: .6)
                : PremiumColors.gold.withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(active ? '● AKTİF' : '○ DURDU',
              style: TextStyle(
                color: active ? PremiumColors.emerald : PremiumColors.gold,
                fontWeight: FontWeight.w800, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _chip(Icons.trending_up, 'Piyasa',
            report.ready ? report.trendLabel : 'Veri bekleniyor',
            color: report.ready && report.trend == TrendDirection.rising
                ? PremiumColors.emerald : PremiumColors.gold)),
          const SizedBox(width: 6),
          Expanded(child: _chip(Icons.psychology_outlined, 'Doğruluk',
            reliability == null ? 'Ölçülmedi'
                : '%${(reliability * 100).toStringAsFixed(0)}',
            color: PremiumColors.emerald)),
          const SizedBox(width: 6),
          Expanded(child: _chip(Icons.shield_outlined, 'Risk', risk,
            color: report.riskElevated
                ? PremiumColors.danger : PremiumColors.gold)),
        ]),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                Color(0xFF253D2B), Color(0xFF18352B)]),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: PremiumColors.gold.withValues(alpha: .32)),
            ),
            child: Row(children: [
              const Icon(Icons.auto_graph, color: PremiumColors.gold),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SON DURUM', style: TextStyle(
                    color: PremiumColors.muted, fontSize: 9,
                    letterSpacing: 1.0)),
                  const SizedBox(height: 3),
                  Text(active
                      ? (report.ready ? report.decisionLabel : 'Veri analiz ediliyor')
                      : 'Bot kapalı · detayları aç',
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
                ],
              )),
              const Icon(Icons.arrow_forward_ios,
                color: PremiumColors.gold, size: 15),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _chip(IconData icon, String title, String value,
      {required Color color}) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF071815).withValues(alpha: .56),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 12, color: PremiumColors.gold),
            const SizedBox(width: 4),
            Expanded(child: Text(title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PremiumColors.muted, fontSize: 10))),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
              style: TextStyle(color: color, fontSize: 12,
                fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class PremiumTechnicalOverview extends StatelessWidget {
  const PremiumTechnicalOverview({
    super.key,
    required this.quote,
    required this.onTap,
  });

  final CoinQuote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final report = analyzeTechnical(quote);
    return PremiumSurface(
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('BTC • 1 saatlik veriler',
            style: TextStyle(color: PremiumColors.muted,
              fontWeight: FontWeight.w700, fontSize: 11))),
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Analiz'),
            style: TextButton.styleFrom(
              foregroundColor: PremiumColors.gold,
              visualDensity: VisualDensity.compact),
          ),
        ]),
        LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth >= 530 ? 4 : 2;
          final tileWidth = (box.maxWidth - (columns - 1) * 8) / columns;
          final cards = <Widget>[
            _tile(Icons.show_chart, 'RSI (14)',
              report.ready ? report.rsi.toStringAsFixed(1) : '—',
              report.ready ? 'Momentum' : 'Veri yok'),
            _tile(Icons.bar_chart, 'MACD',
              report.ready ? report.macdHistogram.toStringAsPrecision(3) : '—',
              'Histogram'),
            _tile(Icons.trending_up, 'Trend',
              report.ready ? _shortTrend(report.trend) : '—', 'EMA20 / 50'),
            _tile(Icons.waves, 'Volatilite',
              report.ready ? '%${report.volatility24hPct.toStringAsFixed(1)}' : '—',
              '24s tahmini'),
          ];
          return Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              for (final card in cards)
                SizedBox(width: tileWidth, child: card),
            ],
          );
        }),
      ]),
    );
  }

  String _shortTrend(TrendDirection trend) => switch (trend) {
    TrendDirection.rising => 'Yükseliş',
    TrendDirection.falling => 'Düşüş',
    TrendDirection.sideways => 'Yatay',
  };

  Widget _tile(IconData icon, String title, String value, String subtitle) =>
      Container(
        padding: const EdgeInsets.fromLTRB(11, 12, 9, 12),
        decoration: BoxDecoration(
          color: PremiumColors.panelRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: PremiumColors.border.withValues(alpha: .55)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: PremiumColors.gold),
            const SizedBox(width: 6),
            Expanded(child: Text(title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PremiumColors.muted, fontSize: 11))),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(
              color: PremiumColors.emerald,
              fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(
            fontSize: 10, color: PremiumColors.muted)),
        ]),
      );
}

class PremiumUpdateTile extends StatelessWidget {
  const PremiumUpdateTile({super.key, required this.onTap, required this.version});
  final VoidCallback onTap;
  final String version;

  @override
  Widget build(BuildContext context) => PremiumSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PremiumColors.goldDim,
                    borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.history_toggle_off,
                    color: PremiumColors.gold, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Güncelleme Geçmişi', style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
                    SizedBox(height: 3),
                    Text('Son yenilikler ve sürüm notları',
                      style: TextStyle(
                        color: PremiumColors.muted, fontSize: 11)),
                  ],
                )),
                Text('v$version',
                  style: const TextStyle(color: PremiumColors.emerald,
                    fontWeight: FontWeight.w700, fontSize: 11)),
                const SizedBox(width: 7),
                const Icon(Icons.chevron_right, color: PremiumColors.gold),
              ]),
            ),
          ),
        ),
      );
}
