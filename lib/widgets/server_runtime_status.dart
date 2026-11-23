import 'package:flutter/material.dart';

import '../services/server_paper_repository.dart';
import 'premium_theme.dart';

/// Read-only diagnostics from the same wallet snapshot as every other screen.
class ServerRuntimeStatusCard extends StatelessWidget {
  const ServerRuntimeStatusCard({super.key, required this.snapshot,
    this.error, this.detailed = false, this.now});

  final ServerPaperSnapshot? snapshot;
  final String? error;
  final bool detailed;
  final DateTime? now;

  String _age(DateTime? at, DateTime clock) {
    if (at == null) return 'Henüz kaydedilmedi';
    final elapsed = clock.toUtc().difference(at);
    if (elapsed.isNegative) return 'Saat doğrulanamadı';
    final age = elapsed.inSeconds < 60 ? '${elapsed.inSeconds} sn önce'
        : elapsed.inMinutes < 60 ? '${elapsed.inMinutes} dk önce'
        : '${elapsed.inHours} sa önce';
    final local = at.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} · $age';
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 14,
        color: PremiumColors.muted)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontSize: 14,
        fontWeight: FontWeight.w700)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final state = snapshot;
    final clock = now ?? DateTime.now();
    final runtime = state?.runtimeStatus ?? const <String, dynamic>{};
    final phase = runtime['phase'];
    final healthy = error == null && (state?.isHealthyAt(clock) ?? false);
    final title = error != null ? 'Panel verisi yenilenemedi'
        : state?.runtimeLabelAt(clock) ?? 'Bot verisi bekleniyor';
    final reason = error ?? runtime['reason']?.toString()
        ?? state?.decisionPlan['reason']?.toString()
        ?? 'İlk sunucu kontrolü henüz alınmadı.';
    final missing = runtime['missingPositionQuotes'];
    final absent = missing is List ? missing.map((e) => '$e').join(', ') : '';
    final checked = runtime['positionsChecked'];
    final total = runtime['positionsTotal'];
    final exits = runtime['exitOrders'];
    final duration = runtime['cycleElapsedSec'];
    final coverage = runtime['scanCoverage'];
    final metrics = <Widget>[
      _metric('Son fiyat gözlemi',
        _age(state?.runtimeDate('marketObservedAt'), clock)),
      _metric('Çıkış denetimi',
        phase == 'SKIPPED' || runtime['exitCheckedAt'] == null
          ? 'Bu tetikte yapılmadı' :
            '${total == null ? checked : '$checked/$total'} pozisyon · $exits çıkış'),
      if (detailed) ...[
        _metric('Son başarılı kontrol', _age(state?.lastSuccessAt, clock)),
        _metric('Döngü süresi', duration is num
          ? '${duration.toStringAsFixed(1)} sn' : 'Henüz ölçülmedi'),
        _metric('Likit evren / kısa liste', runtime['marketObservedAt'] == null
          ? 'Bu tetikte taranmadı'
          : '${state?.tracked ?? 0} / ${runtime['shortlisted'] ?? 0} coin'),
        _metric('Son çıkış kontrolü',
          _age(state?.runtimeDate('exitCheckedAt'), clock)),
        _metric('En eski fiyat zamanı',
          _age(state?.runtimeDate('oldestQuoteAt'), clock)),
      ],
    ];
    return PremiumSurface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.monitor_heart_outlined, size: 20, color: PremiumColors.gold),
          SizedBox(width: 8),
          Text('Botun durumu', style: TextStyle(fontSize: 16,
            fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
          color: healthy ? PremiumColors.emerald : PremiumColors.gold)),
        const SizedBox(height: 6),
        Text(reason, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, bounds) {
          final columns = bounds.maxWidth >= 280 ? 2 : 1;
          final width = (bounds.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ]);
        }),
        if (absent.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Fiyatı alınamayan açık pozisyon: $absent',
            style: const TextStyle(fontSize: 14, color: PremiumColors.danger)),
        ],
        if (detailed && coverage is Map && coverage.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Bu kontroldeki yeni mum sorguları',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final period in const {'hourly': '1 saat', 'fast15m': '15 dakika',
              'minute1m': '1 dakika'}.entries)
            if (coverage[period.key] is Map)
              Padding(padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('${period.value}: '
                  '${(coverage[period.key] as Map)['valid'] ?? 0}/'
                  '${(coverage[period.key] as Map)['requested'] ?? 0} başarılı · '
                  '${(coverage[period.key] as Map)['failed'] ?? 0} eksik',
                  style: const TextStyle(fontSize: 14, color: PremiumColors.muted))),
          const Text('0 sorgu, önbellek kullanımı veya yeni sorgu yapılmaması olabilir.',
            style: TextStyle(fontSize: 12, color: PremiumColors.muted)),
        ],
        if (detailed && runtime['scanCompleted'] != true) ...[
          const SizedBox(height: 10),
          Text(state?.decisionPlan['scanSkippedReason']?.toString()
              ?? 'Bu tetikte geniş mum taraması tamamlanmadı.',
            style: const TextStyle(fontSize: 14, color: PremiumColors.muted)),
        ],
        const SizedBox(height: 10),
        const Text('Fiyatlar sunucudaki periyodik kontrollerde yenilenir.',
          style: TextStyle(fontSize: 12, color: PremiumColors.muted)),
      ],
    ));
  }
}
