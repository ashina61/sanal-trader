import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../widgets/premium_dashboard.dart';
import '../widgets/formatters.dart';

/// Read-only view of the separately persisted, entirely simulated bot wallet.
/// Public data contains no exchange API keys or personal account information.
class ServerPaperCard extends StatefulWidget {
  const ServerPaperCard({super.key});

  @override
  State<ServerPaperCard> createState() => _ServerPaperCardState();
}

class _ServerPaperCardState extends State<ServerPaperCard> {
  static const controls =
      'https://github.com/ashina61/sanal-trader/actions/workflows/paper-bot.yml';

  Map<String, dynamic>? _data;
  String? _error;
  DateTime? _updatedAt;
  bool _loading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 2), (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://raw.githubusercontent.com/ashina61/sanal-trader/'
        'bot-data/state.json?cache=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 404
            ? 'İlk bot çalışması veya kayıt dalı henüz hazır değil'
            : 'GitHub veri erişimi: HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['schema'] != 1) {
        throw const FormatException('Beklenmeyen sunucu cüzdan formatı');
      }
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(decoded);
        _updatedAt = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _num(dynamic n) =>
      n is num && n.toDouble().isFinite ? n.toDouble() : null;

  String _try(dynamic n) {
    final x = _num(n);
    return x == null ? '—' : formatTry(x);
  }

  @override
  Widget build(BuildContext context) {
    final state = _data;
    final last = DateTime.tryParse(state?['lastSuccessAt']?.toString() ?? '');
    final fresh = last != null &&
        DateTime.now().toUtc().difference(last.toUtc()).inMinutes < 20 &&
        !last.toUtc().isAfter(DateTime.now().toUtc());
    final enabled = state?['enabled'] == true;
    final healthy = enabled && fresh && state?['lastError'] == null;
    final list = state?['trades'];
    final trades = list is List ? list.whereType<Map>().take(3).toList() : <Map>[];

    return PremiumSurface(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF154237), Color(0xFF101F1B)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud_outlined, color: PremiumColors.gold, size: 25),
          const SizedBox(width: 9),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('7/24 Sunucu Botu', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800)),
              Text('GitHub Actions · ücretsiz zamanlanmış simülasyon',
                style: TextStyle(
                  color: PremiumColors.muted, fontSize: 10)),
            ],
          )),
          if (_loading)
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          else IconButton(
            tooltip: 'Sunucu verisini yenile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: PremiumColors.gold),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          state == null
              ? 'Sunucudaki ilk sanal çalışma bekleniyor'
              : !enabled ? 'DURDURULDU'
              : healthy ? 'AKTİF · Son kontrol güncel'
              : 'GECİKME / VERİ KONTROLÜ GEREKİYOR',
          style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 12,
            color: healthy ? PremiumColors.emerald : PremiumColors.gold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bu ayrı bir 650 TL sanal sunucu kasasıdır. '
          'Mevcut tarayıcı portföyünden farklıdır ve gerçek para içermez.',
          style: TextStyle(
            color: PremiumColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 13),
        if (state != null) ...[
          Row(children: [
            Expanded(child: _metric('Sunucu sanal kasa',
                _try(state['equityTry']))),
            Expanded(child: _metric('Boşta sanal nakit',
                _try(state['cashTry']))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Gerçekleşen net kâr',
                _try(state['realizedTry']))),
            Expanded(child: _metric('Sanal işlem sayısı',
                '${state['trades'] is List ? (state['trades'] as List).length : 0}')),
          ]),
          const SizedBox(height: 13),
          Text(last == null
              ? 'Henüz başarılı piyasa kontrolü yok'
              : 'Son başarılı kontrol: ${last.toLocal().day.toString().padLeft(2, '0')}.'
                '${last.toLocal().month.toString().padLeft(2, '0')} '
                '${last.toLocal().hour.toString().padLeft(2, '0')}:'
                '${last.toLocal().minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: PremiumColors.muted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(state['lastDecision']?.toString() ?? 'Sinyal bekleniyor',
            style: const TextStyle(fontSize: 12)),
          if (trades.isNotEmpty) ...[
            const Divider(height: 24, color: PremiumColors.border),
            const Text('Son sunucu sanal emirleri',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 7),
            for (final item in trades)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${item['side'] == 'buy' ? 'AL' : 'SAT'} '
                  '${item['symbol'] ?? '?'} · ${_try(item['grossTry'])}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
          if (_updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Gösterge son yenileme: '
                '${_updatedAt!.hour.toString().padLeft(2, '0')}:'
                '${_updatedAt!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: PremiumColors.muted, fontSize: 10)),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text('Veri alınamadı: $_error',
            style: const TextStyle(color: PremiumColors.gold, fontSize: 11)),
        ],
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: controls));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('GitHub Actions kontrol bağlantısı kopyalandı.'),
            ));
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('GitHub bot yönetim linkini kopyala'),
          style: TextButton.styleFrom(foregroundColor: PremiumColors.gold),
        ),
        const Text(
          'Ücretsiz GitHub zamanlaması yaklaşık 5 dakikada bir çalışır; '
          'gecikme veya duraksama olabilir. Aç/Kapat komutları şimdilik '
          'GitHub Actions ekranındadır; aşağıdaki anahtar yalnızca yerel botu yönetir.',
          style: TextStyle(color: PremiumColors.muted, fontSize: 10),
        ),
      ]),
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(
        color: PremiumColors.muted, fontSize: 10)),
      const SizedBox(height: 5),
      FittedBox(fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800,
          color: PremiumColors.emerald))),
    ],
  );
}
