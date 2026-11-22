import 'live_market_data.dart';

/// A bounded, liquid USDT spot universe; not every listed token is safe.
class MarketUniverse {
  const MarketUniverse(this.pairs, this.volumes);
  final Map<String, String> pairs;
  final Map<String, double> volumes;
}

const _excludedBases = <String>{
  'USDT', 'USDC', 'FDUSD', 'TUSD', 'USDD', 'DAI', 'USDP', 'BUSD',
  'EUR', 'TRY', 'BRL', 'GBP', 'AUD', 'PAXG', 'XAUT',
  'EURCV', 'EURI', 'AEUR', 'USTC', 'LUNA', 'WBTC', 'WETH',
  'BFUSD', 'RLUSD', 'PYUSD', 'USD1', 'USDG', 'USDJ', 'UST',
};

bool eligibleUsdtSpotSymbol(String symbol) {
  if (!symbol.endsWith('USDT')) return false;
  final base = symbol.substring(0, symbol.length - 4);
  if (base.length < 2 || base.length > 12 ||
      !RegExp(r'^[A-Z0-9]+$').hasMatch(base) ||
      _excludedBases.contains(base)) return false;
  // Leveraged products and synthetic symbols are not spot coin candidates.
  if (base.endsWith('UP') || base.endsWith('DOWN') ||
      base.endsWith('BULL') || base.endsWith('BEAR') ||
      base.endsWith('3L') || base.endsWith('3S') ||
      base.endsWith('5L') || base.endsWith('5S')) return false;
  return true;
}

/// Select by real 24-hour quote turnover, keeping initial six only when
/// actually returned by the exchange. Never fabricate listings or prices.
MarketUniverse selectMarketUniverse(
  List<dynamic> raw, {
  int limit = 72,
  double minimumVolumeUsdt = 2000000,
}) {
  final candidates = <({String pair, double volume})>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final pair = item['symbol']?.toString() ?? '';
    if (!eligibleUsdtSpotSymbol(pair)) continue;
    final volume = double.tryParse(item['quoteVolume']?.toString() ?? '');
    final last = double.tryParse(item['lastPrice']?.toString() ?? '');
    if (volume == null || !volume.isFinite || volume < minimumVolumeUsdt ||
        last == null || !last.isFinite || last <= 0) continue;
    candidates.add((pair: pair, volume: volume));
  }
  candidates.sort((a, b) => b.volume.compareTo(a.volume));
  final selected = <String, String>{};
  final volumes = <String, double>{};
  // Keep core pairs if valid and liquid; otherwise do not force a dead market.
  for (final pair in trackedPairs.keys) {
    for (final row in candidates) {
      if (row.pair == pair) {
        selected[pair] = trackedPairs[pair]!;
        volumes[pair] = row.volume;
        break;
      }
    }
  }
  for (final row in candidates) {
    if (selected.length >= limit) break;
    if (selected.containsKey(row.pair)) continue;
    final base = row.pair.substring(0, row.pair.length - 4);
    selected[row.pair] = base.toLowerCase();
    volumes[row.pair] = row.volume;
  }
  return MarketUniverse(selected, volumes);
}
