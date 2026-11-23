import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'formatters.dart';
import 'premium_theme.dart';

/// One-screen account summary. The existing detailed accounting stays intact.
class CompactWalletCard extends StatelessWidget {
  const CompactWalletCard({
    super.key, required this.snapshot, required this.onTrades,
    this.onRefresh, this.loading = false, this.error,
  });

  final ServerPaperSnapshot? snapshot;
  final VoidCallback onTrades;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final net = s?.equityTry;
    final pnl = s?.pnlTry;
    final positive = (pnl ?? 0) >= 0;
    final healthy = error == null && (s?.isHealthyAt(DateTime.now()) ?? false);
    final open = (s?.holdings.length ?? 0) + (s?.shorts.length ?? 0);
    final update = s?.lastSuccessAt?.toLocal();
    final updated = update == null ? 'Son kontrol bekleniyor'
        : 'Son kontrol ${update.hour.toString().padLeft(2, '0')}:'
          '${update.minute.toString().padLeft(2, '0')}';
    return PremiumSurface(
      padding: const EdgeInsets.all(14),
      gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF16382E), Color(0xFF101F1B)]),
      borderColor: const Color(0xFF376550),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: PremiumColors.gold, size: 18),
          const SizedBox(width: 6),
          const Expanded(child: Text('TEK SANAL KASA', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: PremiumColors.gold, letterSpacing: .5))),
          Icon(healthy ? Icons.check_circle_outline : Icons.schedule,
              size: 14, color: healthy
                  ? PremiumColors.emerald : PremiumColors.gold),
          const SizedBox(width: 4),
          Text(healthy ? 'Güncel' : 'Kontrol gerekli',
              style: const TextStyle(fontSize: 10,
                  color: PremiumColors.muted)),
          IconButton(tooltip: 'Kasa verisini yenile',
            visualDensity: VisualDensity.compact,
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 19)),
        ]),
        const SizedBox(height: 2),
        Text(net == null ? '—' : formatTry(net),
            style: const TextStyle(fontSize: 31,
                fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 3),
        Row(children: [
          Text(pnl == null ? 'İlk değer bekleniyor' :
              '${pnl >= 0 ? '+' : ''}${formatTry(pnl)}',
              style: TextStyle(color: positive
                  ? PremiumColors.emerald : PremiumColors.danger,
                  fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          const Flexible(child: Text('başlangıçtan beri · net tahmini',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: PremiumColors.muted, fontSize: 10))),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, size) {
          final wide = size.maxWidth > 300;
          final width = (size.maxWidth - (wide ? 16 : 8)) / (wide ? 3 : 2);
          final items = [
            ('Nakit', s == null ? '—' : formatTry(s.cashTry)),
            ('Pozisyon', '$open'),
            ('İşlem', s == null ? '—' : '${s.trades.length}'),
          ];
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final metric in items)
              SizedBox(width: width, child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF152A24),
                  borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.$1, style: const TextStyle(
                        color: PremiumColors.muted, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(metric.$2, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ]))),
          ]);
        }),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: Text(error ?? updated, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: PremiumColors.muted, fontSize: 10))),
          TextButton.icon(
              onPressed: onTrades,
              icon: const Icon(Icons.receipt_long_outlined, size: 15),
              label: const Text('İşlemler',
                  style: TextStyle(fontSize: 11))),
        ]),
      ]),
    );
  }
}
