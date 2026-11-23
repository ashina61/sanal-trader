import 'dart:convert';

import 'package:http/http.dart' as http;

/// Read-only, public simulated server wallet. Never a real exchange account.
/// Its balance is intentionally independent from the local Flutter wallet.
class ServerPaperSnapshot {
  ServerPaperSnapshot._(this._raw);
  final Map<String, dynamic> _raw;

  factory ServerPaperSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Sunucu cüzdan sürümü desteklenmiyor');
    }
    for (final key in ['cashTry', 'equityTry', 'initialCashTry',
        if (json.containsKey('netLiquidationTry')) 'netLiquidationTry']) {
      final number = json[key];
      if (number is! num || !number.toDouble().isFinite || number < 0) {
        throw FormatException('Sunucu kasasında geçersiz alan: $key');
      }
    }
    if (json['holdings'] is! Map || json['trades'] is! List) {
      throw const FormatException('Sunucu pozisyon/işlem kaydı bozuk');
    }
    if (json['shorts'] != null && json['shorts'] is! Map) {
      throw const FormatException('Sunucu SHORT pozisyon kaydı bozuk');
    }
    return ServerPaperSnapshot._(Map<String, dynamic>.unmodifiable(json));
  }

  double? number(String key) {
    final value = _raw[key];
    if (value is num && value.toDouble().isFinite) return value.toDouble();
    return null;
  }

  double get cashTry => number('cashTry')!;
  double get markEquityTry => number('equityTry')!;
  bool get hasNetLiquidation => number('netLiquidationTry') != null;
  double get equityTry => number('netLiquidationTry') ?? markEquityTry;
  double get startingTry => number('initialCashTry')!;
  double get pnlTry => equityTry - startingTry;
  double get realizedTry => number('realizedTry') ?? 0.0;
  double get feesTry => number('paidFeesTry') ?? 0.0;
  int get tracked => (number('tracked') ?? 0).toInt();
  int get cycles => (number('cycles') ?? 0).toInt();
  bool get enabled => _raw['enabled'] == true;
  String? get error => _raw['lastError']?.toString();
  String get decision => _raw['lastDecision']?.toString() ?? 'İşlem sinyali bekleniyor';

  DateTime? _date(String key) {
    final value = _raw[key];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  DateTime? get lastSuccessAt => _date('lastSuccessAt');
  DateTime? get lastRunAt => _date('lastRunAt');
  Map<String, dynamic> get runtimeStatus => _map('runtimeStatus');
  DateTime? runtimeDate(String key) {
    final value = runtimeStatus[key];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  String runtimeLabelAt(DateTime time) {
    if (!enabled) return 'Bot duraklatıldı';
    if (error != null || runtimeStatus['phase'] == 'ERROR') {
      return 'Kontrol tamamlanamadı';
    }
    final last = lastSuccessAt;
    final now = time.toUtc();
    if (last == null) return 'Başarılı kontrol bekleniyor';
    if (last.isAfter(now)) return 'Kontrol zamanı doğrulanamadı';
    if (now.difference(last) >= const Duration(minutes: 5)) {
      return 'Piyasa kontrolü gecikti';
    }
    final quote = runtimeDate('oldestQuoteAt');
    if (quote != null && (quote.isAfter(now) ||
        now.difference(quote) >= const Duration(minutes: 5))) {
      return 'Piyasa verisi eski';
    }
    return switch (runtimeStatus['phase']) {
      'SKIPPED' => 'Tekrarlanan tetik atlandı',
      'PROTECTED' => 'Koruyucu çıkışlar kaydedildi',
      'DEGRADED' => 'Kontrol tamamlandı · kısmi mum verisi',
      'COMPLETE' => decisionPlan['action'] == 'WAIT'
          ? 'Kontrol güncel · fırsat bekleniyor'
          : 'Kontrol güncel · karar kaydedildi',
      _ => 'Ayrıntılı durum kaydı bekleniyor',
    };
  }
  DateTime? get lastTriggerAt => _date('lastTriggerAt');
  DateTime? get lastScheduledTriggerAt => _date('lastScheduledTriggerAt');
  String? get lastTriggerEvent {
    final value = _raw['lastTriggerEvent'];
    return value == 'schedule' || value == 'push' ||
        value == 'workflow_dispatch' ? value as String : null;
  }
  bool isHealthyAt(DateTime time) {
    final last = lastSuccessAt;
    final runtime = runtimeStatus;
    final source = runtimeDate('oldestQuoteAt');
    return enabled && error == null && last != null &&
        runtime['phase'] != 'ERROR' && runtime['phase'] != 'DEGRADED' &&
        (source == null || (!source.isAfter(time.toUtc()) &&
          time.toUtc().difference(source) < const Duration(minutes: 5))) &&
        !last.isAfter(time.toUtc()) &&
        time.toUtc().difference(last) < const Duration(minutes: 5);
  }

  Map<String, dynamic> _map(String key) {
    final raw = _raw[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }
  Map<String, dynamic> get holdings => _map('holdings');
  Map<String, dynamic> get shorts => _map('shorts');
  Map<String, dynamic> get marksTry => _map('marksTry');
  Map<String, dynamic> get directionStats => _map('directionStats');
  Map<String, dynamic> get performance => _map('performance');
  Map<String, dynamic> get objective => _map('objective');
  Map<String, dynamic> get tradeLearning => _map('tradeLearning');
  Map<String, dynamic> get coverageStats => _map('coverageStats');
  Map<String, dynamic> get smartMoney => _map('smartMoney');
  Map<String, dynamic> get freeDexRadar => _map('freeDexRadar');
  Map<String, dynamic> get publicApiHealth => _map('publicApiHealth');

  /// Only real, persisted virtual-wallet observations.
  List<Map<String, dynamic>> get equityHistory {
    final raw = _raw['equityHistory'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(
      (entry) => Map<String, dynamic>.from(entry),
    ).toList(growable: false);
  }
  /// Server-supplied evidence from the most recent autonomous decision.
  /// Older bot-data snapshots safely show an empty analysis.
  Map<String, dynamic> get decisionPlan => _map('decisionPlan');

  List<Map<String, dynamic>> get trades {
    final source = _raw['trades'];
    if (source is! List) return [];
    return source.whereType<Map>().map(
      (entry) => Map<String, dynamic>.from(entry),
    ).toList(growable: false);
  }
}

/// A single shared fetch instance is owned by HomeScreen and passed to
/// Panel / Portfolio / Bot / Profit / History. No separate screen wallets.
class ServerPaperRepository {
  ServerPaperRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const sourceUrl =
      'https://raw.githubusercontent.com/ashina61/sanal-trader/bot-data/state.json';
  static const controlsUrl =
      'https://github.com/ashina61/sanal-trader/actions/workflows/paper-bot.yml';

  Future<ServerPaperSnapshot> load() async {
    final uri = Uri.parse('$sourceUrl?refresh=${DateTime.now().millisecondsSinceEpoch}');
    // Only CORS-safelisted Accept: non-safelisted Cache-Control can
    // trigger a failed OPTIONS preflight on a public GitHub raw file.
    // The timestamp query already avoids stale CDN cache entries.
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 14));
    if (response.statusCode != 200) {
      throw Exception(response.statusCode == 404
          ? 'İlk sunucu sanal cüzdanı henüz oluşturulmadı'
          : 'GitHub sunucu cüzdanı HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const FormatException('Sunucu yanıtı geçersiz');
    return ServerPaperSnapshot.fromJson(Map<String, dynamic>.from(json));
  }

  void dispose() => _client.close();
}
