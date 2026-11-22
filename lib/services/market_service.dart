import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/coin_quote.dart';

class MarketService {
  MarketService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const coinIds = [
    'bitcoin', 'ethereum', 'solana', 'ripple', 'binancecoin', 'dogecoin',
  ];

  // Kişisel MVP: key'siz CoinGecko public/demo erişimi.
  // Anahtarlı kullanım için anahtarı APK içine koyma; backend proxy kullan.
  Future<List<CoinQuote>> fetchQuotes() async {
    final url = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
      'vs_currency': 'try',
      'ids': coinIds.join(','),
      'order': 'market_cap_desc',
      'per_page': '10',
      'page': '1',
      'sparkline': 'true',
    });
    final response = await _client.get(url, headers: {
      'accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      throw Exception('Fiyat sağlayıcısının istek limiti doldu (429). Biraz sonra yenile.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Fiyat sağlayıcısı API erişimini reddetti (${response.statusCode}).');
    }
    if (response.statusCode != 200) {
      throw Exception('Piyasa verisi alınamadı (HTTP ${response.statusCode}).');
    }
    final json = jsonDecode(response.body);
    if (json is! List) throw Exception('Beklenmeyen piyasa verisi biçimi.');
    final quotes = json
        .whereType<Map<String, dynamic>>()
        .map(CoinQuote.fromJson)
        .where((quote) => quote.priceTry > 0)
        .toList();
    if (quotes.isEmpty) throw Exception('Piyasa verisi boş döndü.');
    return quotes;
  }

  void dispose() => _client.close();
}
