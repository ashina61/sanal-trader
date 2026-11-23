import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/server_paper_repository.dart';
import 'formatters.dart';
import 'premium_theme.dart';

String _money(dynamic value) => value is num && value.toDouble().isFinite
    ? formatTry(value.toDouble()) : '—';

String _sideLabel(dynamic code) => switch (code) {
  'buy' => 'SPOT AL',
  'sell' => 'SPOT SAT',
  'short' => 'SHORT AÇ',
  'cover' => 'SHORT KAPAT',
  _ => 'SANAL İŞLEM',
};

/// Read-only status summary of the single autonomous server wallet.
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
    final healthy = error == null && (snapshot?.isHealthyAt(DateTime.now()) ?? false);
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
                  const Text('ANA SANAL KASA · SUNUCU BOTU', style: TextStyle(
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
    final healthy = error == null && (state?.isHealthyAt(DateTime.now()) ?? false);
    final longs = state?.holdings ?? {};
    final shorts = state?.shorts ?? {};
    final plan = state?.decisionPlan ?? const <String, dynamic>{};
    final positionHealth = plan['positionHealth'] is List
        ? (plan['positionHealth'] as List).whereType<Map>().take(12).toList()
        : <Map>[];
    final researchSignals = (plan['researchSignals'] as num?)?.toInt() ?? 0;
    final sideStats = state?.directionStats ?? const <String, dynamic>{};
    final ai = plan['aiBrain'] is Map
        ? (plan['aiBrain'] as Map) : const <String, dynamic>{};
    final aiStatus = ai['status']?.toString() ?? 'NOT_CONFIGURED';
    final aiText = switch (aiStatus) {
      'TRADE' => 'AI ONAYLI İŞLEM',
      'WAIT' => 'AI BEKLE DEDİ',
      'FALLBACK' => 'AI HATASI · KURAL MOTORU AKTİF',
      'PROTECTIVE_EXIT' => 'KORUYUCU EMİR · AI ATLANDI',
      'RISK_REDUCTION' => 'RİSK AZALTIMI · SPOT SATIŞ',
      'ROTATION_EXIT' => 'PORTFÖY ROTASYONU · TEKNİK ÇIKIŞ',
      'NO_CANDIDATE' => 'AI ADAY BEKLİYOR',
      _ => 'AI BAĞLI DEĞİL · KURAL MOTORU AKTİF',
    };
    final action = plan['action']?.toString() ?? 'WAIT';
    final actionText = switch (action) {
      'BUY' => 'SPOT AL',
      'SELL' => 'SPOT SAT',
      'SHORT' => '1x SHORT AÇ',
      'COVER' => '1x SHORT KAPAT',
      _ => 'BEKLE',
    };
    final learnedClosures = plan['signalStats'] is Map
        ? (plan['signalStats'] as Map).values.whereType<Map>()
            .fold<int>(0, (sum, item) =>
                sum + ((item['closed'] as num?)?.toInt() ?? 0))
        : 0;
    final contextClosures = plan['contextStats'] is Map
        ? (plan['contextStats'] as Map).values.whereType<Map>()
            .fold<int>(0, (sum, item) =>
                sum + ((item['closed'] as num?)?.toInt() ?? 0))
        : 0;
    final forward = plan['forwardEvidence'] is Map
        ? (plan['forwardEvidence'] as Map) : const <String, dynamic>{};
    final forwardCount = (forward['samples'] as num?)?.toInt() ?? 0;
    final forwardPending = (forward['pending'] as num?)?.toInt() ?? 0;
    final forwardAvg = forward['avgNetPct'] is num
        ? '${(forward['avgNetPct'] as num).toStringAsFixed(2)}%'
        : '—';
    final forwardWins = forward['winRatePct'] is num
        ? '${(forward['winRatePct'] as num).toStringAsFixed(1)}%'
        : '—';
    final aiApproved = forward['aiApproved'] is Map
        ? (forward['aiApproved'] as Map) : const <String, dynamic>{};
    final aiWaited = forward['aiWaited'] is Map
        ? (forward['aiWaited'] as Map) : const <String, dynamic>{};
    final aiApprovedMean = aiApproved['avgNetPct'] is num
        ? '${(aiApproved['avgNetPct'] as num).toStringAsFixed(2)}%'
        : '—';
    final aiWaitedMean = aiWaited['avgNetPct'] is num
        ? '${(aiWaited['avgNetPct'] as num).toStringAsFixed(2)}%'
        : '—';
    final scanStats = plan['scanStats'] is Map
        ? (plan['scanStats'] as Map) : const <String, dynamic>{};
    final entryGuard = plan['evidenceGuard'] is Map
        ? (plan['evidenceGuard'] as Map) : const <String, dynamic>{};
    final entryBuy = entryGuard['BUY'] is Map
        ? (entryGuard['BUY'] as Map) : const <String, dynamic>{};
    final entryShort = entryGuard['SHORT'] is Map
        ? (entryGuard['SHORT'] as Map) : const <String, dynamic>{};
    final scanDuration = scanStats['candleElapsedSec'] is num
        ? '${(scanStats['candleElapsedSec'] as num).toStringAsFixed(1)} sn'
        : '—';
    final marketPulse = plan['marketPulse'] is Map
        ? (plan['marketPulse'] as Map) : const <String, dynamic>{};
    final newsStatus = plan['newsStatus']?.toString() ?? 'UNAVAILABLE';
    final newsHeadlines = plan['newsHeadlines'] is List
        ? (plan['newsHeadlines'] as List).whereType<Map>().take(3).toList()
        : <Map>[];
    final candidates = plan['candidates'] is List
        ? (plan['candidates'] as List).whereType<Map>().take(5).toList()
        : <Map>[];
    final cronAt = state?.lastScheduledTriggerAt?.toLocal();
    final cronText = cronAt == null
        ? 'GitHub otomatik zamanlayıcı: henüz doğrulanmadı'
        : 'GitHub otomatik zamanlayıcı: son tetik '
          '${cronAt.day.toString().padLeft(2, '0')}.'
          '${cronAt.month.toString().padLeft(2, '0')} '
          '${cronAt.hour.toString().padLeft(2, '0')}:'
          '${cronAt.minute.toString().padLeft(2, '0')}';
    final triggerText = switch (state?.lastTriggerEvent) {
      'schedule' => 'otomatik zamanlayıcı',
      'push' => 'kod güncellemesi',
      'workflow_dispatch' => 'manuel / dış tetik',
      _ => null,
    };
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
              Text('Otonom Bot · SPOT AL/SAT + SHORT',
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
          'Tek sanal kasa: tüm işlemleri arka plandaki sunucu botu yapar. '
          'Uygulama yalnızca sonucu gösterir.',
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
            Expanded(child: _metric('Açık SPOT', '${longs.length}')),
            Expanded(child: _metric('Açık SHORT · 1x', '${shorts.length}')),
            Expanded(child: _metric('İşlem', '${state.trades.length}')),
          ]),
          const SizedBox(height: 5),
          Text('İzlenen açık pozisyon: ${plan['openPositionsChecked'] ?? longs.length + shorts.length}'
            ' · Koruyucu çıkış adayı: ${plan['protectiveExitCandidates'] ?? '—'}',
            style: const TextStyle(fontSize: 9, color: PremiumColors.muted)),
          const SizedBox(height: 11),
          const Text('SON GERÇEK SANAL EMİRLER',
            style: TextStyle(fontSize: 11,
              color: PremiumColors.gold, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          if (state.trades.isEmpty)
            const Text('Henüz hiçbir sanal emir gerçekleşmedi',
              style: TextStyle(fontSize: 10, color: PremiumColors.muted))
          else
            for (final trade in state.trades.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(
                    _sideLabel(trade['side']),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                      color: trade['side'] == 'sell' || trade['side'] == 'cover'
                        ? PremiumColors.gold : PremiumColors.emerald))),
                  Expanded(child: Text(
                    trade['symbol']?.toString() ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10))),
                  Text(
                    trade['side'] == 'sell' || trade['side'] == 'cover'
                      ? 'Net ${_money(trade['realizedPnlTry'])}'
                      : _money(trade['grossTry']),
                    style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: (trade['side'] == 'sell' || trade['side'] == 'cover')
                          && trade['realizedPnlTry'] is num
                          && (trade['realizedPnlTry'] as num) < 0
                        ? PremiumColors.danger : PremiumColors.emerald),
                  ),
                ]),
              ),
          const SizedBox(height: 10),
          const Text('Gerçek sanal kapanışlardan SPOT/SHORT analizi',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: PremiumColors.gold)),
          const SizedBox(height: 7),
          for (final side in const ['long', 'short'])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${side == 'long' ? 'SPOT' : 'SHORT'} · '
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
            const Text('Açık pozisyonlar · tahmini kapanış neti',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 6),
            if (positionHealth.isNotEmpty)
              for (final item in positionHealth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(children: [
                    Expanded(child: Text(
                      '${item['side'] ?? 'POZİSYON'} ${item['symbol'] ?? ''}'
                      '${item['ageHours'] is num ? ' · ${item['ageHours']} sa' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11,
                        color: PremiumColors.muted),
                    )),
                    Text(
                      _money(item['estimatedCloseNetTry']),
                      style: TextStyle(fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: (item['estimatedCloseNetTry'] is num &&
                            (item['estimatedCloseNetTry'] as num) < 0)
                          ? PremiumColors.danger : PremiumColors.emerald),
                    ),
                  ]),
                )
            else ...[
              for (final entry in longs.entries.take(8))
                Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Text('SPOT ${entry.key} · maliyet '
                    '${entry.value is Map ? _money((entry.value as Map)['costTry']) : '—'}',
                    style: const TextStyle(
                      fontSize: 10, color: PremiumColors.muted))),
              for (final entry in shorts.entries.take(8))
                Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Text('SHORT ${entry.key} · teminat '
                    '${entry.value is Map ? _money((entry.value as Map)['marginTry']) : '—'}',
                    style: const TextStyle(
                      fontSize: 10, color: PremiumColors.muted))),
            ],
            const Text('Net: son gözlenen fiyat ve varsayılan çıkış '
              'komisyonu ile yaklaşık değer; henüz gerçekleşmiş işlem değildir.',
              style: TextStyle(fontSize: 9, color: PremiumColors.muted)),
            const SizedBox(height: 7),
          ],
          Text(updated == null ? 'Henüz başarılı döngü kaydı yok'
                : 'Son başarılı piyasa kontrolü: '
                  '${updated.day.toString().padLeft(2,'0')}.'
                  '${updated.month.toString().padLeft(2,'0')} '
                  '${updated.hour.toString().padLeft(2,'0')}:'
                  '${updated.minute.toString().padLeft(2,'0')}',
              style: const TextStyle(
                fontSize: 11, color: PremiumColors.muted)),
          const SizedBox(height: 5),
          Text(cronText, style: const TextStyle(
            fontSize: 10, color: PremiumColors.muted)),
          if (triggerText != null) ...[
            const SizedBox(height: 3),
            Text('Son çalıştırma türü: $triggerText',
              style: const TextStyle(
                fontSize: 10, color: PremiumColors.muted)),
          ],
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Yapay zekâ beyni · $aiText',
                    style: const TextStyle(color: PremiumColors.gold,
                      fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                if (ai['reason'] != null) ...[
                  const SizedBox(height: 3),
                  Align(alignment: Alignment.centerLeft,
                    child: Text(ai['reason'].toString(),
                      style: const TextStyle(fontSize: 10,
                        color: PremiumColors.muted))),
                ],
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
                  Expanded(child: _metric('Gerçek 1dk mum',
                    '${plan['minutePairs'] is num ? plan['minutePairs'] : '—'} coin')),
                  Expanded(child: _metric('Sinyal öğrenme',
                    '$learnedClosures kapanış')),
                  Expanded(child: _metric('Bağlam öğrenme',
                    '$contextClosures kapanış')),
                ]),
                const SizedBox(height: 5),
                Text('Grafik tarama süresi: $scanDuration · '
                  '${scanStats['publicRequests'] ?? '—'} mum isteği · '
                  '${scanStats['workers'] ?? '—'} eşzamanlı okuma',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 9)),
                const SizedBox(height: 4),
                Text(
                  'Giriş freni: SPOT ${entryBuy['blocked'] == true ? 'KORUMADA' : 'AÇIK'} · '
                  'SHORT ${entryShort['blocked'] == true ? 'KORUMADA' : 'AÇIK'}',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 10)),
                const SizedBox(height: 5),
                const Text('Öğrenme sadece tamamlanan sanal işlemin net sonucundan '
                  'yapılır. Az örneklemde etki çok düşüktür; geçmişte olmayan sonuç '
                  'üretilmez.',
                  style: TextStyle(color: PremiumColors.muted, fontSize: 9)),
                const SizedBox(height: 11),
                const Text('İleriye dönük sinyal doğrulaması · 60 dk',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: PremiumColors.gold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _metric('Ölçülen', '$forwardCount sinyal')),
                  Expanded(child: _metric('Bekleyen', '$forwardPending sinyal')),
                  Expanded(child: _metric('Ort. net', forwardAvg)),
                ]),
                const SizedBox(height: 5),
                Text('Komisyon + varsayılan kayma sonrası isabet: $forwardWins. '
                  'Gerçek emir değil: seçilen sinyalin bir saat sonraki '
                  'gözlenen fiyatı ölçülür. İlk 30 sonuçtan önce puan '
                  'ayarı yapılmaz; tutarlı zararlar yeni girişe fren olabilir.',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 9)),
                const SizedBox(height: 5),
                Text(
                  'AI onayladığı: ${aiApproved['samples'] ?? 0} sinyal · '
                  'ort. $aiApprovedMean  |  '
                  'AI beklediği: ${aiWaited['samples'] ?? 0} sinyal · '
                  'ort. $aiWaitedMean',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 9),
                ),
                const SizedBox(height: 4),
                Text('Cüzdan dolu olsa da gözlemsel aday: $researchSignals · '
                  'bu adaylar ekstra emir veya ikinci kasa oluşturmaz.',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 9)),
                const SizedBox(height: 9),
                Align(alignment: Alignment.centerLeft, child: Text(
                  'Piyasa genişliği · 24s',
                  style: const TextStyle(color: PremiumColors.gold,
                    fontSize: 11, fontWeight: FontWeight.w800),
                )),
                const SizedBox(height: 4),
                Text(
                  'Yükselen: ${marketPulse['up'] ?? '—'} · '
                  'Düşen: ${marketPulse['down'] ?? '—'} · '
                  'Yatay: ${marketPulse['flat'] ?? '—'} · '
                  'Ortanca: ${marketPulse['medianChange24hPct'] ?? '—'}%',
                  style: const TextStyle(
                    color: PremiumColors.muted, fontSize: 10),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(
                  'Haber radarı · $newsStatus',
                  style: const TextStyle(color: PremiumColors.gold,
                    fontSize: 11, fontWeight: FontWeight.w800),
                )),
                const SizedBox(height: 3),
                const Text('Başlıklar bilgilendirme ve yeni giriş risk kontrolü '
                  'içindir; tek başına alım/satım emri değildir.',
                  style: TextStyle(color: PremiumColors.muted, fontSize: 9)),
                for (final story in newsHeadlines)
                  Padding(padding: const EdgeInsets.only(top: 4),
                    child: Align(alignment: Alignment.centerLeft,
                      child: Text(
                        '${story['source'] ?? 'Haber'} · ${story['title'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PremiumColors.muted, fontSize: 10),
                      ),
                    ),
                  ),
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
                          '${candidate['action'] == 'SHORT' ? 'SHORT AÇ' : 'SPOT AL'} · '
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
          'GitHub zamanlaması gecikebilir. İşlemleri yalnızca '
          'sunucu botu yürütür; uygulamadan manuel emir verilmez. '
          '1x sanal SHORT modeli borçlanma/fonlama maliyetini içermez.',
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
                'Bu kayıtlar uygulamanın tek sanal kasasına aittir. '
                'Gerçek borsada işlem yapılmaz.',
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
