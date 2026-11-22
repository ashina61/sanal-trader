import 'package:flutter/material.dart';
import '../models/coin_quote.dart';
import '../services/technical_analysis.dart';
import '../widgets/premium_dashboard.dart';

enum RadarMode { volume, gainers, losers, signals }

class MarketRadarScreen extends StatefulWidget {
  const MarketRadarScreen({
    super.key, required this.quotes, required this.onOpen,
  });
  final Map<String, CoinQuote> quotes;
  final ValueChanged<CoinQuote> onOpen;

  @override
  State<MarketRadarScreen> createState() => _MarketRadarScreenState();
}

class _MarketRadarScreenState extends State<MarketRadarScreen> {
  RadarMode _mode = RadarMode.volume;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fresh = widget.quotes.values.where((q) =>
      q.priceTry.isFinite && q.priceTry > 0 && q.isFresh).toList();
    final filtered = fresh.where((q) =>
      q.name.toLowerCase().contains(_query) ||
      q.symbol.toLowerCase().contains(_query)).toList();
    if (_mode == RadarMode.gainers) {
      filtered.sort((a, b) => b.change24h.compareTo(a.change24h));
    } else if (_mode == RadarMode.losers) {
      filtered.sort((a, b) => a.change24h.compareTo(b.change24h));
    } else if (_mode == RadarMode.signals) {
      filtered.removeWhere((q) {
        final a = analyzeTechnical(q);
        return !a.ready || a.score < .35 ||
            a.trend == TrendDirection.falling;
      });
      filtered.sort((a, b) =>
        analyzeTechnical(b).score.compareTo(analyzeTechnical(a).score));
    } else {
      filtered.sort((a, b) =>
        b.volume24hUsdt.compareTo(a.volume24hUsdt));
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final coin = filtered[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PremiumSurface(
              padding: EdgeInsets.zero,
              radius: 15,
              child: PremiumMarketTile(
                quote: coin, onTap: () => widget.onOpen(coin),
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PremiumSectionTitle(title: 'Piyasa Radarı'),
          const SizedBox(height: 8),
          Text('${fresh.length} güncel coin taranıyor · TL sanal piyasa',
            style: const TextStyle(
              color: PremiumColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (text) => setState(
              () => _query = text.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Piyasada coin ara…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(RadarMode.volume, 'Hacim', Icons.view_list_outlined),
              _chip(RadarMode.gainers, 'Yükselenler', Icons.trending_up),
              _chip(RadarMode.losers, 'Düşenler', Icons.trending_down),
              _chip(RadarMode.signals, 'Teknik adaylar', Icons.auto_graph),
            ]),
          ),
          const SizedBox(height: 10),
          const Text(
            'Teknik adaylar geçmiş fiyat verisi olan coinlerden oluşur. '
            'Sinyal görmek otomatik alım emri verileceği anlamına gelmez.',
            style: TextStyle(color: PremiumColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 11),
          if (filtered.isEmpty)
            const PremiumSurface(child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Bu filtrede güncel veri yok.',
                style: TextStyle(color: PremiumColors.muted)),
            )),
        ]);
      },
    );
  }

  Widget _chip(RadarMode mode, String label, IconData icon) {
    final selected = _mode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14,
            color: selected ? PremiumColors.background : PremiumColors.gold),
          const SizedBox(width: 5),
          Text(label),
        ]),
        labelStyle: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: selected ? PremiumColors.background : Colors.white),
        selectedColor: PremiumColors.gold,
        backgroundColor: PremiumColors.panel,
        side: const BorderSide(color: PremiumColors.border),
        onSelected: (_) => setState(() => _mode = mode),
      ),
    );
  }
}
