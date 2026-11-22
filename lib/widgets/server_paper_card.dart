import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/server_paper_repository.dart';
import 'formatters.dart';
import 'premium_dashboard.dart';

String _money(dynamic value) => value is num && value.toDouble().isFinite
    ? formatTry(value.toDouble()) : '—';

String _sideLabel(dynamic code) => switch (code) {
  'buy' => 'LONG AÇ',
  'sell' => 'LONG KAPAT',
  'short' => 'SHORT AÇ',
  'cover' => 'SHORT KAPAT',
  _ => 'SANAL İŞLEM',
};

/// Small, shared status summary for the Panel and local Portfolio tab.
class ServerPaperSummaryTile extends StatelessWidget {
  const ServerPaperSummaryTile({
    super.key, required this.snapshot, required this.loading,
    required this.error, required this.onTap,
  });
  final ServerPaperSnapshot? snapshot;
  final bool loading;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final healthy = snapshot?.isHealthyAt(DateTime.now()) ?? false;
    final status = snapshot == null
        ? (loading ? 'Sunucu verisi yükleniyor' : (error ?? 'Bağlantı bekleniyor'))
        : !snapshot!.enabled ? 'Durduruldu'
        : healthy ? 'Son kontrol güncel'
        : 'Kontrol gecikmiş veya veri hatası var';
    return PremiumSurface(
      padding: EdgeInsets.zero,
      borderColor: PremiumColors.gold.withValues(alpha: .45),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              const Icon(Icons.cloud_outlined, color: PremiumColors.gold, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SUNUCU · AYRI SANAL KASA', style: TextStyle(
                    color: PremiumColors.gold, fontSize: 10,
                    fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(snapshot == null ? '—' : formatTry(snapshot!.equityTry),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 3),
                  Text(status,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PremiumColors.muted, fontSize: 10)),
                ],
              )),
              if (loading)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.chevron_right, color: PremiumColors.gold),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Server snapshot is supplied by HomeScreen's ONE centralized read.
class ServerPaperCard extends StatelessWidget {
  const ServerPaperCard({
    super.key, required this.snapshot, required this.loading,
    required this.error, required this.onRefresh, required this.onOpenTrades,
  });
  final ServerPaperSnapshot? snapshot;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onOpenTrades;

  @override
  Widget build(BuildContext context) {
    final state = snapshot;
    final updated = state?.lastSuccessAt?.toLocal();
    final healthy = state?.isHealthyAt(DateTime.now()) ?? false;
    final longs = state?.holdings ?? {};
    final shorts = state?.shorts ?? {};
    final marks = state?.marksTry ?? {};
    final sideStats = state?.directionStats ?? const <String, dynamic>{};
    final plan = state?.decisionPlan ?? const <String, dynamic>{};
    final action = plan['action']?.toString() ?? 'WAIT';
    final actionText = switch (action) {
      'BUY' => 'SPOT AL / LONG',
      'SELL' => 'SPOT SAT / LONG KAPAT',
      'SHORT' => '1x SHORT AÇ',
      'COVER' => '1x SHORT KAPAT',
      _ => 'BEKLE',
    };
    final candidates = plan['candidates'] is List
        ? (plan['candidates'] as List).whereType<Map>().take(5).toList()
        : <Map>[];
    return PremiumSurface(
      gradient: const LinearGradient(
        colors: [Color(0xFF164034), Color(0xFF0D1E1B)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.dns_outlined, color: PremiumColors.gold, size: 23),
          const SizedBox(width: 9),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sunucu Botu · 1x LONG / SHORT',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              Text('Ücretsiz GitHub Actions · periyodik sanal emir',
                style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
            ],
          )),
          IconButton(
            tooltip: 'Sunucu kasasını yenile',
            onPressed: loading ? null : onRefresh,
            icon: loading ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: PremiumColors.gold),
          ),
        ]),
        const SizedBox(height: 9),
        Text(state == null ? 'SUNUCU VERİSİ BEKLENİYOR'
            : !state.enabled ? 'DURDURULDU'
            : healthy ? 'ÇALIŞIYOR · SON KONTROL GÜNCEL'
            : 'SON KONTROL GECİKMİŞ / VERİ HATASI',
          style: TextStyle(
            color: healthy ? PremiumColors.emerald : PremiumColors.gold,
            fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Bu hesap tarayıcıdaki yerel bot cüzdanından AYRIDIR. '
          'Aynı 650 TL iki farklı sanal test hesabıdır.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 11)),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text('Veri uyarısı: $error', style: const TextStyle(
            color: PremiumColors.danger, fontSize: 11)),
        ],
        if (state != null) ...[
          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: _metric('Toplam sanal değer', _money(state.equityTry))),
            Expanded(child: _metric('Sanal nakit', _money(state.cashTry))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Kasa değişimi', _money(state.pnlTry))),
            Expanded(child: _metric('Gerçekleşen net', _money(state.realizedTry))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Açık LONG', '${longs.length}')),
            Expanded(child: _metric('Açık SHORT · 1x', '${shorts.length}')),
            Expanded(child: _metric('İşlem', '${state.trades.length}')),
          ]),
          const SizedBox(height: 14),
          const Text('Gerçek sanal kapanışlardan LONG/SHORT öğrenme',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: PremiumColors.gold)),
          const SizedBox(height: 7),
          for (final side in const ['long', 'short'])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${side.toUpperCase()} · '
                '${sideStats[side] is Map
                  ? ((sideStats[side] as Map)['closed'] ?? 0)
                  : 0} kapanış · Net '
                '${sideStats[side] is Map
                  ? _money((sideStats[side] as Map)['realizedTry'])
                  : '—'}',
                style: const TextStyle(fontSize: 11,
                  color: PremiumColors.muted),
              ),
            ),
          const SizedBox(height: 13),
          if (longs.isNotEmpty || shorts.isNotEmpty) ...[
            const Divider(color: PremiumColors.border),
            const Text('Açık sanal pozisyonlar',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 8),
            for (final entry in longs.entries.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('LONG ${entry.key} · maliyet '
                  '${entry.value is Map ? _money((entry.value as Map)['costTry']) : '—'}',
                  style: const TextStyle(fontSize: 11,
                    color: PremiumColors.emerald)),
              ),
            for (final entry in shorts.entries.take(8)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('SHORT ${entry.key} · teminat '
                  '${entry.value is Map ? _money((entry.value as Map)['marginTry']) : '—'}',
                  style: const TextStyle(
                    fontSize: 11, color: PremiumColors.gold)),
              ),
              if (entry.value is Map &&
                  (entry.value as Map)['entryPriceTry'] is num &&
                  (entry.value as Map)['quantity'] is num &&
                  marks[entry.key] is num)
                Padding(padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    'Açık fiyat farkı (ücret hariç): '
                    '${_money(
                      ((entry.value as Map)['entryPriceTry'] as num).toDouble() *
                      ((entry.value as Map)['quantity'] as num).toDouble() -
                      (marks[entry.key] as num).toDouble() *
                      ((entry.value as Map)['quantity'] as num).toDouble()
                    )}',
                    style: const TextStyle(fontSize: 10,
                      color: PremiumColors.muted)),
                ),
            ],
          ],
          Text(updated == null ? 'Henüz başarılı döngü kaydı yok'
                : 'Son başarılı piyasa kontrolü: '
                  '${updated.day.toString().padLeft(2,'0')}.'
                  '${updated.month.toString().padLeft(2,'0')} '
                  '${updated.hour.toString().padLeft(2,'0')}:'
                  '${updated.minute.toString().padLeft(2,'0')}',
              style: const TextStyle(
                fontSize: 11, color: PremiumColors.muted)),
          const SizedBox(height: 12),
          Card(
            color: PremiumColors.panel,
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const Text('Otonom Karar Merkezi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              subtitle: Text(
                '$actionText · ${plan['marketRegime']?.toString() ?? 'Analiz bekleniyor'}',
                style: const TextStyle(
                  color: PremiumColors.gold, fontSize: 11)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    plan['reason']?.toString() ?? state.decision,
                    style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _metric('Piyasa evreni',
                    '${plan['universe'] is num ? plan['universe'] : state.tracked} coin')),
                  Expanded(child: _metric('Teknik analiz',
                    '${plan['reviewed'] is num ? plan['reviewed'] : '—'} coin')),
                  Expanded(child: _metric('Grafik bulunan',
                    '${plan['historyPairs'] is num ? plan['historyPairs'] : '—'} coin')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _metric('Seçilen',
                    plan['symbol']?.toString() ?? 'İşlem yok')),
                  Expanded(child: _metric('Sanal emir',
                    _money(plan['amountTry']))),
                ]),
                if (plan['rejectReasons'] is Map &&
                    (plan['rejectReasons'] as Map).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('İşlem açılmama nedenleri',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                  ),
                  const SizedBox(height: 5),
                  for (final reason in (plan['rejectReasons'] as Map).entries.take(6))
                    Padding(padding: const EdgeInsets.only(bottom: 3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${reason.key}: ${reason.value} coin',
                          style: const TextStyle(
                            fontSize: 10, color: PremiumColors.muted)),
                      ),
                    ),
                ],
                if (candidates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('En güçlü teknik adaylar',
                      style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 5),
                  for (final candidate in candidates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Align(alignment: Alignment.centerLeft,
                        child: Text(
                          '${candidate['symbol'] ?? '?'} · '
                          '${candidate['action'] == 'SHORT' ? 'SHORT' : 'AL'} · '
                          'Puan ${candidate['score'] ?? '?'}',
                          style: const TextStyle(
                            fontSize: 10, color: PremiumColors.muted),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Bot spot AL/SAT, 1x sanal SHORT aç/kapat veya BEKLE '
                  'kararını kendi verir. Veri hatası, yüksek risk veya '
                  'yetersiz sinyalde işlem açmayabilir. '
                  'Bu bölüm geçmişte gerçekleşen gerçek sanal emirden '
                  've yatırım tavsiyesinden farklıdır.',
                  style: TextStyle(
                    color: PremiumColors.muted, fontSize: 10)),
              ],
            ),
          ),
          if (state.error != null)
            Text('Sunucu hatası: ${state.error}',
              style: const TextStyle(
                fontSize: 11, color: PremiumColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenTrades,
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: const Text('Sunucu işlemleri ve hesap geçmişi'),
          ),
        ],
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(
              const ClipboardData(text: ServerPaperRepository.controlsUrl),
            );
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('GitHub bot yönetim bağlantısı kopyalandı.'),
            ));
          },
          icon: const Icon(Icons.copy, size: 15),
          label: const Text('GitHub Bot Yönetimi bağlantısını kopyala'),
          style: TextButton.styleFrom(foregroundColor: PremiumColors.gold),
        ),
        const Text(
          'GitHub zamanlaması gecikebilir. Tarayıcıdaki yerel bot anahtarı '
          'sunucu botunu açıp kapatmaz. Finansman/borçlanma maliyeti '
          'bu 1x sanal SHORT modelinde hesaplanmıyor.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 10)),
      ]),
    );
  }

  Widget _metric(String title, String amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: PremiumColors.muted)),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(amount, style: const TextStyle(
          color: PremiumColors.emerald, fontSize: 15,
          fontWeight: FontWeight.w900)),
      ),
    ],
  );
}

/// Complete persisted SERVER history, never local browser trade records.
class ServerPaperTradesScreen extends StatelessWidget {
  const ServerPaperTradesScreen({
    super.key, required this.snapshots, required this.onRefresh,
  });
  final ValueListenable<ServerPaperSnapshot?> snapshots;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ServerPaperSnapshot?>(
    valueListenable: snapshots,
    builder: (context, snapshot, _) {
      final trades = snapshot?.trades ?? [];
      return Scaffold(
      appBar: AppBar(
        title: const Text('Sunucu sanal işlem geçmişi'),
        actions: [
          IconButton(onPressed: onRefresh,
              tooltip: 'Sunucu verilerini yenile',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const PremiumSectionTitle(title: 'Sunucu Botu · Kayıtlar'),
              const SizedBox(height: 8),
              const Text(
                'Bu işlemler yalnızca ücretsiz sunucu botunun '
                'ayrı 650 TL sanal kasasına aittir.',
                style: TextStyle(color: PremiumColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 13),
              if (snapshot != null)
                ServerPaperSummaryTile(
                  snapshot: snapshot, loading: false, error: null,
                  onTap: onRefresh,
                ),
              const SizedBox(height: 16),
              if (trades.isEmpty)
                const PremiumSurface(
                  child: Text('Kayıtlı sunucu işlemi bulunamadı.',
                    style: TextStyle(color: PremiumColors.muted)),
                ),
              for (final t in trades)
                Card(
                  child: ListTile(
                    leading: Icon(
                      t['side'] == 'short' || t['side'] == 'cover'
                          ? Icons.trending_down : Icons.trending_up,
                      color: t['side'] == 'short' || t['side'] == 'cover'
                          ? PremiumColors.gold : PremiumColors.emerald,
                    ),
                    title: Text('${_sideLabel(t['side'])} · ${t['symbol'] ?? '—'}'),
                    subtitle: Text(
                      '${t['at']?.toString() ?? ''} · '
                      'Komisyon ${_money(t['feeTry'])}\n'
                      '${t['reason']?.toString() ?? ''}',
                      style: const TextStyle(fontSize: 10)),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(t['grossTry']),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (t['side'] == 'sell' || t['side'] == 'cover')
                          Text('Net ${_money(t['realizedPnlTry'])}',
                            style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    },
  );
}
