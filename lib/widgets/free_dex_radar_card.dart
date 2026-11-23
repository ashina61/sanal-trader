import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'premium_theme.dart';

/// Free public DEX observations: never qualified smart-money trade signals.
class FreeDexRadarCard extends StatelessWidget {
  const FreeDexRadarCard({super.key, required this.snapshot});

  final ServerPaperSnapshot? snapshot;

  String _short(String value) {
    if (value.length < 16) return value;
    return '${value.substring(0, 7)}…${value.substring(value.length - 5)}';
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot?.freeDexRadar ?? const <String, dynamic>{};
    final status = data['status']?.toString() ?? 'NOT_STARTED';
    final available = status == 'OBSERVING';
    final partial = status == 'DEGRADED';
    final wallets = data['walletsObserved'] is List
        ? (data['walletsObserved'] as List).whereType<Map>().take(8).toList()
        : <Map>[];
    final history = data['history'] is List
        ? (data['history'] as List).whereType<Map>().toList().reversed.take(6)
            .toList()
        : <Map>[];
    final checked = DateTime.tryParse(data['checkedAt']?.toString() ?? '')
        ?.toLocal();
    final checkedLabel = checked == null ? 'İlk tarama bekleniyor'
        : '${checked.hour.toString().padLeft(2, '0')}:'
          '${checked.minute.toString().padLeft(2, '0')}';
    final statusText = available ? 'GÖZLEMLENİYOR'
        : partial ? 'KISMİ VERİ'
        : status == 'UNAVAILABLE' ? 'ERİŞİLEMİYOR' : 'BEKLİYOR';
    return PremiumSurface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.travel_explore_outlined, color: PremiumColors.gold,
              size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Ücretsiz DEX Keşfi',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text(statusText, style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w800,
              color: available ? PremiumColors.emerald : PremiumColors.gold)),
        ]),
        const SizedBox(height: 8),
        Text(
          data['reason']?.toString() ??
              'Solana ve Base için ilk ücretsiz veri taraması bekleniyor.',
          style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _count('Havuz', data['poolsScreened'])),
          Expanded(child: _count('İşlem', data['tradesChecked'])),
          Expanded(child: _count('Adres', data['observedSenders'])),
        ]),
        const SizedBox(height: 7),
        Text('Son veri: $checkedLabel · 12 dk önbellek · GeckoTerminal',
            style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
        const SizedBox(height: 6),
        const Text(
          'Buradaki adresler kârlı akıllı cüzdan olarak doğrulanmış DEĞİL. '
          'Aynı kişinin birden fazla adresi olabilir; LP, mint, fon kaynağı '
          've 30 günlük kâr kanıtı yok. Sinyaller işleme dönüşmez.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
        if (history.isNotEmpty)
          Material(color: Colors.transparent, child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Gözlenen 3+ adres kümesi (${history.length})',
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
            children: [
              for (final item in history)
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Align(alignment: Alignment.centerLeft,
                    child: Text(
                      '${item['chain'] ?? '—'} · ${item['symbol'] ?? '—'} · '
                      '${item['senderCount'] ?? '—'} farklı adres · '
                      'ONAYSIZ',
                      style: const TextStyle(fontSize: 12)))),
            ],
          )),
        if (wallets.isNotEmpty)
          Material(color: Colors.transparent, child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('İşlem gönderen adresler (${data['observedSenders']})',
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
            children: [
              for (final wallet in wallets)
                Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Align(alignment: Alignment.centerLeft,
                    child: Text(
                      '${wallet['chain'] ?? '—'} · '
                      '${_short(wallet['address']?.toString() ?? '')} · '
                      '${wallet['observedBuys'] ?? 0} alış / '
                      '${wallet['observedSells'] ?? 0} satış',
                      style: const TextStyle(fontSize: 12)))),
              const Padding(padding: EdgeInsets.only(bottom: 7),
                child: Text('Örneklemde görülen gönderici adreslerdir; '
                    'yatırımcı kimliği ya da başarı sıralaması değildir.',
                    style: TextStyle(color: PremiumColors.muted,
                        fontSize: 11))),
            ],
          )),
      ],
    ));
  }

  Widget _count(String name, dynamic value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontSize: 11,
          color: PremiumColors.muted)),
      Text(value?.toString() ?? '—', style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800)),
    ],
  );
}
