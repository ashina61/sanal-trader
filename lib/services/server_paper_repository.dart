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
    for (final key in ['cashTry', 'equityTry', 'initialCashTry']) {
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
  double get equityTry => number('equityTry')!;
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
  bool isHealthyAt(DateTime time) {
    final last = lastSuccessAt;
    return enabled && error == null && last != null &&
        !last.isAfter(time.toUtc()) &&
        time.toUtc().difference(last) < const Duration(minutes: 20);
  }

  Map<String, dynamic> _map(String key) {
    final raw = _raw[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }
  Map<String, dynamic> get holdings => _map('holdings');
  Map<String, dynamic> get shorts => _map('shorts');
  Map<String, dynamic> get marksTry => _map('marksTry');
  Map<String, dynamic> get directionStats => _map('directionStats');

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
