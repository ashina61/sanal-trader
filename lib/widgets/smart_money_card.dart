import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'premium_theme.dart';

/// Read-only wallet-research status from the single server snapshot.
class SmartMoneyCard extends StatelessWidget {
  const SmartMoneyCard({super.key, required this.snapshot});
  final ServerPaperSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final data = snapshot?.smartMoney ?? const <String, dynamic>{};
    final status = data['status']?.toString() ?? 'NOT_CONFIGURED';
    final buys = data['newSignals'] is List
        ? (data['newSignals'] as List).whereType<Map>().toList()
        : <Map>[];
    final sells = data['saleAlerts'] is List
        ? (data['saleAlerts'] as List).whereType<Map>().toList()
        : <Map>[];
    final history = data['history'] is List
        ? (data['history'] as List).whereType<Map>().toList().reversed.take(6).toList()
        : <Map>[];
    final ready = status == 'READY';
    final checked = DateTime.tryParse(data['checkedAt']?.toString() ?? '')?.toLocal();
    final checkedLabel = checked == null ? '—'
        : checked.hour.toString().padLeft(2, '0') + ':' +
          checked.minute.toString().padLeft(2, '0');
    return PremiumSurface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.hub_outlined, size: 20,
              color: ready ? PremiumColors.emerald : PremiumColors.gold),
          const SizedBox(width: 8),
          const Expanded(child: Text('Akıllı Para · Solana / Base',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text(ready ? 'İZLEME' : 'VERİ BEKLENİYOR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: ready ? PremiumColors.emerald : PremiumColors.gold)),
        ]),
        const SizedBox(height: 8),
        Text(ready
            ? (data['walletCount'] ?? 0).toString() + '/15 cüzdan · ' +
              buys.length.toString() + ' yeni alım · ' +
              sells.length.toString() + ' satış uyarısı'
            : data['reason']?.toString() ?? 'Cüzdan sağlayıcısı bağlanmadı.',
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 5),
        Text('Son kontrol: $checkedLabel · Salt okunur · Tek sanal kasa',
            style: const TextStyle(fontSize: 11, color: PremiumColors.muted)),
        if (ready && buys.isEmpty && sells.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 7),
            child: Text('Yeni, uygun 3-cüzdan sinyali yok.',
                style: TextStyle(fontSize: 11, color: PremiumColors.muted))),
        if (history.isNotEmpty)
          Material(color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Sinyal kayıtları (son 24 saat)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              children: [
                for (final item in history)
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: Align(alignment: Alignment.centerLeft,
                      child: Text(
                        (item['type'] == 'SMART_WALLET_SELL'
                          ? 'SATIŞ TAKİBİ' : '3+ ALIM') + ' · ' +
                        (item['symbol'] ?? '—').toString() + ' · ' +
                        (item['chain'] ?? '—').toString() + ' · ' +
                        (item['walletCount'] ?? 1).toString() + ' cüzdan',
                        style: const TextStyle(fontSize: 12)))),
                const Text('Sinyaller dış sağlayıcı bildirimine dayanır. '
                    'Bağımsız zincir doğrulaması veya otomatik emir yok.',
                    style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
              ],
            )),
      ],
    ));
  }
}
