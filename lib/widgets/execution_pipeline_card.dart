import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'premium_theme.dart';

/// Six deterministic diagnostics, not six separately paid AI agents.
class ExecutionPipelineCard extends StatelessWidget {
  const ExecutionPipelineCard({super.key, required this.snapshot});

  final ServerPaperSnapshot? snapshot;
  static const _names = [
    'PULSE', 'IMPACT', 'EDGE', 'SIZE', 'ENTRY', 'EXIT'
  ];
  static const _icons = [
    Icons.graphic_eq, Icons.auto_graph, Icons.rule,
    Icons.shield_outlined, Icons.login, Icons.logout,
  ];

  @override
  Widget build(BuildContext context) {
    final plan = snapshot?.decisionPlan ?? const <String, dynamic>{};
    final audit = plan['executionPipeline'] is Map
        ? Map<String, dynamic>.from(plan['executionPipeline'] as Map)
        : <String, dynamic>{};
    final rawStages = audit['stages'] is List
        ? (audit['stages'] as List).whereType<Map>().toList()
        : <Map>[];
    final status = audit['status']?.toString() ?? 'PENDING';
    final active = status == 'PASSED';
    final blocked = status == 'BLOCKED';
    final hasAudit = rawStages.isNotEmpty;
    final at = DateTime.tryParse(plan['at']?.toString() ?? '')?.toLocal();
    final atText = at == null ? 'İlk kontrol bekleniyor'
        : '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    return PremiumSurface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_tree_outlined, size: 19,
              color: PremiumColors.gold),
          const SizedBox(width: 7),
          const Expanded(child: Text('6 Aşamalı Karar Motoru',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(active ? 'ONAY' : blocked ? 'RET' : 'İZLEME',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: blocked ? PremiumColors.danger :
                  active ? PremiumColors.emerald : PremiumColors.gold)),
        ]),
        const SizedBox(height: 4),
        Text('Son karar $atText · ${audit['symbol'] ?? 'Yeni giriş yok'}',
            style: const TextStyle(fontSize: 11,
                color: PremiumColors.muted)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, bounds) {
          final columns = bounds.maxWidth >= 480 ? 3 : 2;
          final cell = (bounds.maxWidth - (columns - 1) * 7) / columns;
          return Wrap(spacing: 7, runSpacing: 7, children: [
            for (var index = 0; index < _names.length; index++)
              SizedBox(width: cell, child: _stageTile(
                index, hasAudit ? rawStages.firstWhere(
                  (item) => item['name'] == _names[index],
                  orElse: () => {}) : {},
              )),
          ]);
        }),
        const SizedBox(height: 8),
        Text(audit['reason']?.toString() ??
            'Sadece uygun adayda Binance emir defteri sorgulanır. '
            'Çıkış kuralları önceliklidir.',
            style: const TextStyle(
                color: PremiumColors.muted, fontSize: 11)),
        if (hasAudit)
          Material(color: Colors.transparent, child: ExpansionTile(
            dense: true, tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Karar aşamaları ve maliyetler',
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
            children: [
              for (final item in rawStages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 62, child: Text(
                        item['name']?.toString() ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 11, color: PremiumColors.gold))),
                      Expanded(child: Text(
                        item['detail']?.toString() ?? 'Henüz ölçülmedi',
                        style: const TextStyle(fontSize: 11))),
                    ])),
              if (audit['spreadPct'] is num)
                Text('Makas: %${audit['spreadPct']} · '
                    'Gidiş-dönüş varsayımsal maliyet: '
                    '%${audit['frictionPct'] ?? '—'}',
                    style: const TextStyle(fontSize: 11,
                        color: PremiumColors.muted)),
            ],
          )),
        const Text('Emir defteri anlık görüntüdür; ileri fiyat tahmini ve '
            'gerçek emir dolum garantisi değildir.',
            style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
      ]),
    );
  }

  Widget _stageTile(int index, Map item) {
    final status = item['status']?.toString() ?? 'PENDING';
    final good = const {'OBSERVED', 'CHECKED', 'PAPER_ESTIMATE', 'COST_ONLY',
      'ARMED'}.contains(status);
    final bad = status == 'BLOCKED';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF192C26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C463C))),
      child: Row(children: [
        Icon(_icons[index], size: 16, color: bad ? PremiumColors.danger
            : good ? PremiumColors.emerald : PremiumColors.gold),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_names[index], style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800)),
            Text(good ? 'Ölçüldü' : bad ? 'Reddedildi' : 'Beklemede',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PremiumColors.muted,
                    fontSize: 9)),
          ])),
      ]),
    );
  }
}
