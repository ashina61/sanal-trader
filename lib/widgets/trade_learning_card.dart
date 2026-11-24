import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'formatters.dart';
import 'premium_theme.dart';

/// Audit from completed single-wallet paper orders; no fabricated model ROI.
class TradeLearningCard extends StatelessWidget {
  const TradeLearningCard({super.key, required this.snapshot});
  final ServerPaperSnapshot? snapshot;

  String _money(Object? value) => value is num
      ? '${value >= 0 ? '+' : ''}${formatTry(value.toDouble())}' : '—';

  @override
  Widget build(BuildContext context) {
    final stats = snapshot?.tradeLearning ?? const <String, dynamic>{};
    final recent = stats['recent10'] is Map
        ? stats['recent10'] as Map : const {};
    final closed = stats['closed'] is Map
        ? stats['closed'] as Map : const {};
    final objective = snapshot?.objective ?? const <String, dynamic>{};
    final first = snapshot?.decisionPlan['profitFirst'] is Map
        ? snapshot!.decisionPlan['profitFirst'] as Map : const {};
    final breakout = first['realizedSpotBreakout'] is Map
        ? first['realizedSpotBreakout'] as Map : const {};
    final trend = first['realizedSpotTrend'] is Map
        ? first['realizedSpotTrend'] as Map : const {};
    final short = first['realizedShort'] is Map
        ? first['realizedShort'] as Map : const {};
    final recentNet = recent['netRealizedTry'];
    final color = recentNet is num && recentNet < 0
        ? PremiumColors.danger : PremiumColors.emerald;
    final byExit = stats['byExit'] is Map ? stats['byExit'] as Map : const {};
    return PremiumSurface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.psychology_alt_outlined,
              color: PremiumColors.gold, size: 19),
          const SizedBox(width: 7),
          const Expanded(child: Text('İşlemlerden Öğrenme',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text(stats.isEmpty ? 'İLK RAPOR' : 'GÖZLEM',
              style: const TextStyle(color: PremiumColors.gold,
                  fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        const Text('Gerçekleşmiş sanal çıkışlar · komisyon dahil net sonuç',
            style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _stat('Son 10 net', _money(recentNet), color)),
          Expanded(child: _stat('Kapanan', '${closed['closed'] ?? '—'}')),
          Expanded(child: _stat('Kayıp serisi',
              '${stats['recentLossStreak'] ?? '—'}')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _stat('Ort. net çıkış',
              _money(recent['avgNetPerCloseTry']))),
          Expanded(child: _stat('Kâr/zarar faktörü',
              closed['profitFactor']?.toString() ?? '—')),
        ]),
        if ((breakout['closed'] as num? ?? 0) > 0)
          Material(color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero, dense: true,
              title: const Text('Hangi strateji gerçekten kazandı?',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800)),
              subtitle: const Text('Kapanmış sanal işlemlerin net sonucu',
                  style: TextStyle(fontSize: 10,
                      color: PremiumColors.muted)),
              children: [
                _setupLine('SPOT kırılım', breakout),
                _setupLine('SPOT trend', trend),
                _setupLine('SHORT', short),
                const Padding(padding: EdgeInsets.only(bottom: 7),
                    child: Text(
                  'Az sayıda kapanmış işlem gelecekte kazanç garantisi değildir. '
                  'Küçük SPOT denemeleri ayrıca ileri piyasa verisi ve risk '
                  'kontrollerinden geçmek zorundadır.',
                  style: TextStyle(fontSize: 10,
                      color: PremiumColors.muted))),
              ],
            )),
        if (objective['scenarioNetAfterSlippageTry'] is num) ...[
          const SizedBox(height: 9),
          Text('5 baz puan ek çıkış kayması senaryosu: '
              '${formatTry((objective['scenarioNetAfterSlippageTry'] as num).toDouble())}',
              style: const TextStyle(fontSize: 11,
                  color: PremiumColors.muted)),
        ],
        if (byExit.isNotEmpty) Material(color: Colors.transparent,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero, dense: true,
            title: const Text('Çıkış türüne göre net sonuç',
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
            children: [
              for (final entry in byExit.entries)
                Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: Text(entry.key.toString(),
                        style: const TextStyle(fontSize: 11))),
                    Text('${(entry.value as Map)['closed'] ?? 0} çıkış · '
                         '${_money((entry.value as Map)['netRealizedTry'])}',
                        style: const TextStyle(fontSize: 11)),
                  ])),
            ],
          )),
        const SizedBox(height: 5),
        const Text('Örneklem en fazla son 100 emir kaydından gelir. '
            'Geçmiş sonuçlar ileri dönük kesin kazanç veya '
            'otomatik işlem yetkisi değildir.',
            style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
      ],
    ));
  }

  Widget _setupLine(String name, Map data) {
    final wins = data['wins'] ?? 0;
    final closed = data['closed'] ?? 0;
    final net = data['netTry'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(name,
            style: const TextStyle(fontSize: 11))),
        Text('$wins/$closed · ${_money(net)}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: net is num && net < 0
                    ? PremiumColors.danger : PremiumColors.emerald)),
      ]));
  }

  Widget _stat(String name, String value, [Color? color]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: PremiumColors.muted)),
      const SizedBox(height: 3),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
              color: color)),
    ],
  );
}
