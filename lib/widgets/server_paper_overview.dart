import 'package:flutter/material.dart';
import '../services/server_paper_repository.dart';
import 'formatters.dart';
import 'premium_dashboard.dart';

/// One prominent, read-only overview of the actual background paper wallet.
/// The separate browser wallet is never added to this total.
class ServerPaperOverview extends StatelessWidget {
  const ServerPaperOverview({
    super.key, required this.snapshot, required this.loading,
    required this.error, required this.onOpenBot,
    required this.onOpenTrades, required this.onRefresh,
  });
  final ServerPaperSnapshot? snapshot;
  final bool loading;
  final String? error;
  final VoidCallback onOpenBot;
  final VoidCallback onOpenTrades;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final healthy = s?.isHealthyAt(DateTime.now()) ?? false;
    final growth = s == null ? null : s.equityTry - s.startingTry;
    final growthPct = s == null || s.startingTry <= 0
        ? null : growth! / s.startingTry * 100;
    final positive = (growth ?? 0) >= 0;
    final points = (s?.equityHistory ?? const <Map<String, dynamic>>[])
        .map((e) => e['equityTry']).whereType<num>()
        .map((n) => n.toDouble()).where((n) => n.isFinite && n >= 0)
        .toList(growable: false);
    final ai = s?.decisionPlan['aiBrain'];
    final status = ai is Map ? ai['status']?.toString() : '';
    final aiText = switch (status) {
      'TRADE' => 'Groq AI işlem seçti',
      'WAIT' => 'Groq AI bekle dedi',
      'FALLBACK' => 'AI erişilemedi · kurallar aktif',
      'NO_CANDIDATE' => 'AI uygun aday bekliyor',
      'PROTECTIVE_EXIT' => 'Koruyucu çıkış kararı',
      'ROTATION_EXIT' => 'Teknik portföy rotasyonu',
      _ => 'AI karar kaydı bekleniyor',
    };
    final last = s?.lastSuccessAt?.toLocal();
    final lastTrade = s != null && s.trades.isNotEmpty ? s.trades.first : null;
    return PremiumSurface(
      padding: const EdgeInsets.all(16),
      gradient: const LinearGradient(begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A493C), Color(0xFF112A23), Color(0xFF0C1B18)]),
      borderColor: const Color(0xFF44705D),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_graph_outlined,
            size: 22, color: PremiumColors.gold),
          const SizedBox(width: 8),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('OTONOM BOT · ANA SANAL KASA',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  letterSpacing: .5, color: PremiumColors.gold)),
              Text('Hedef: net büyüme ve risk kontrolü',
                style: TextStyle(fontSize: 10, color: PremiumColors.muted)),
            ],
          )),
          IconButton(
            tooltip: 'Sunucu verisini yenile',
            onPressed: loading ? null : onRefresh,
            icon: loading ? const SizedBox(width: 17, height: 17,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, color: PremiumColors.gold),
          ),
        ]),
        const SizedBox(height: 10),
        Text(s == null ? '—' : formatTry(s.equityTry),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(growth == null ? 'Güncel değer bekleniyor'
            : '${growth >= 0 ? '+' : ''}${formatTry(growth)} · '
              '${growthPct! >= 0 ? '+' : ''}${growthPct.toStringAsFixed(2)}%',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
            color: growth == null ? PremiumColors.muted :
              positive ? PremiumColors.emerald : PremiumColors.danger)),
        const SizedBox(height: 12),
        if (points.length > 1) ...[
          const Text('GERÇEK SANAL KASA EĞRİSİ',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
              letterSpacing: .5, color: PremiumColors.muted)),
          const SizedBox(height: 6),
          SizedBox(height: 70, width: double.infinity,
            child: CustomPaint(painter: _EquityLine(points, positive))),
          const SizedBox(height: 10),
        ] else
          const Padding(padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Grafik, gerçek kontrollerle oluşuyor.',
              style: TextStyle(color: PremiumColors.muted, fontSize: 10))),
        Row(children: [
          Expanded(child: _stat('Sanal nakit',
            s == null ? '—' : formatTry(s.cashTry))),
          Expanded(child: _stat('Net kapanış',
            s == null ? '—' : formatTry(s.realizedTry))),
          Expanded(child: _stat('İşlem',
            s == null ? '—' : '${s.trades.length}')),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: PremiumColors.background.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s == null ? 'Sunucu verisi yükleniyor'
                  : !s.enabled ? 'DURDURULDU'
                  : healthy ? '● Güncel piyasa kontrolü'
                  : '⚠ Son kontrol gecikmiş',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: healthy ? PremiumColors.emerald : PremiumColors.gold)),
              const SizedBox(height: 4),
              Text('${aiText}${last == null ? '' :
                ' · ${last.hour.toString().padLeft(2, '0')}:'
                '${last.minute.toString().padLeft(2, '0')}'}',
                style: const TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
              if (lastTrade != null) ...[
                const SizedBox(height: 4),
                Text('Son sanal işlem: ${lastTrade['symbol'] ?? '—'} · '
                  '${lastTrade['side'] ?? '—'} · '
                  '${lastTrade['grossTry'] is num
                    ? formatTry((lastTrade['grossTry'] as num).toDouble()) : '—'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
              ],
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(error!, style: const TextStyle(fontSize: 10,
                  color: PremiumColors.danger)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: onOpenBot,
            icon: const Icon(Icons.smart_toy_outlined, size: 16),
            label: const Text('Bot merkezi'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: onOpenTrades,
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: const Text('İşlemler'))),
        ]),
        const SizedBox(height: 7),
        const Text('Sadece sunucu sanal kasasıdır; yerel demo dahil değil. '
          'Kâr garantisi yoktur.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 9)),
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        color: PremiumColors.muted, fontSize: 10)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(
        fontWeight: FontWeight.w800, fontSize: 12)),
    ],
  );
}

/// Direct holdings from the same server wallet shown on Home and Bot tabs.
class ServerPaperPositionsPanel extends StatelessWidget {
  const ServerPaperPositionsPanel({
    super.key, required this.snapshot, required this.onOpenTrades,
  });
  final ServerPaperSnapshot? snapshot;
  final VoidCallback onOpenTrades;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    if (s == null) {
      return const PremiumSurface(child: Text('Sunucu portföyü yükleniyor...'));
    }
    final positions = <Widget>[];
    for (final e in s.holdings.entries) {
      if (e.value is! Map) continue;
      final pos = e.value as Map;
      final q = pos['quantity'];
      final cost = pos['costTry'];
      final mark = s.marksTry[e.key];
      final current = q is num && mark is num
          ? q.toDouble() * mark.toDouble() : null;
      final gain = current != null && cost is num
          ? current - cost.toDouble() : null;
      positions.add(_position('LONG', e.key, current, gain));
    }
    for (final e in s.shorts.entries) {
      if (e.value is! Map) continue;
      final pos = e.value as Map;
      final entry = pos['entryPriceTry'];
      final q = pos['quantity'];
      final mark = s.marksTry[e.key];
      final margin = pos['marginTry'];
      final gain = entry is num && q is num && mark is num
          ? q.toDouble() * (entry.toDouble() - mark.toDouble()) : null;
      final current = margin is num && gain != null
          ? margin.toDouble() + gain : null;
      positions.add(_position('SHORT', e.key, current, gain));
    }
    return PremiumSurface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ANA SUNUCU PORTFÖYÜ',
          style: TextStyle(fontWeight: FontWeight.w900,
            fontSize: 12, color: PremiumColors.gold)),
        const SizedBox(height: 7),
        Text('${s.holdings.length} LONG · ${s.shorts.length} SHORT'
          ' · Nakit ${formatTry(s.cashTry)}',
          style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
        const SizedBox(height: 10),
        if (positions.isEmpty)
          const Text('Açık sanal pozisyon yok.',
            style: TextStyle(color: PremiumColors.muted))
        else ...positions,
        TextButton.icon(onPressed: onOpenTrades,
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: const Text('Sunucu işlem geçmişi')),
      ]),
    );
  }

  Widget _position(String side, String symbol, double? value,
      double? gain) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(side == 'LONG' ? Icons.trending_up : Icons.trending_down,
        size: 17, color: side == 'LONG'
          ? PremiumColors.emerald : PremiumColors.gold),
      const SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${side} · ${symbol}', style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800)),
          Text(value == null ? 'Güncel fiyat yok'
            : 'Sanal değer ${formatTry(value)}',
            style: const TextStyle(fontSize: 10,
              color: PremiumColors.muted)),
        ],
      )),
      Text(gain == null ? '—' : '${gain > 0 ? '+' : ''}${formatTry(gain)}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
          color: gain == null ? PremiumColors.muted :
            gain >= 0 ? PremiumColors.emerald : PremiumColors.danger)),
    ]),
  );
}

class _EquityLine extends CustomPainter {
  _EquityLine(this.values, this.up);
  final List<double> values;
  final bool up;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final range = high - low;
    final line = Path();
    final fill = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = range < 0.0000001 ? size.height * .5
        : size.height - 6 - (values[i] - low) / range * (size.height - 12);
      if (i == 0) line.moveTo(x, y); else line.lineTo(x, y);
      fill.lineTo(x, y);
    }
    fill..lineTo(size.width, size.height)..close();
    final color = up ? PremiumColors.emerald : PremiumColors.danger;
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .20), color.withValues(alpha: .01)],
      ).createShader(Offset.zero & size));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _EquityLine old) =>
    old.up != up || old.values.length != values.length ||
      (values.isNotEmpty && old.values.isNotEmpty &&
       values.last != old.values.last);
}
