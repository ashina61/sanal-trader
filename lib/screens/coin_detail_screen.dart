import '../widgets/premium_dashboard.dart';
import "dart:math" as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import '../services/portfolio_repository.dart';
import '../services/trade_engine.dart';
import '../widgets/formatters.dart';
import '../widgets/mini_chart.dart';
import 'expert_analysis_screen.dart';

class CoinDetailScreen extends StatefulWidget {
  const CoinDetailScreen({
    super.key,
    required this.quote,
    required this.portfolio,
    required this.repository,
  });

  final CoinQuote quote;
  final Portfolio portfolio;
  final PortfolioRepository repository;

  @override
  State<CoinDetailScreen> createState() => _CoinDetailScreenState();
}

class _CoinDetailScreenState extends State<CoinDetailScreen> {
  final _amountController = TextEditingController();
  TradeSide _side = TradeSide.buy;
  bool _busy = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountController.text.trim().replaceAll(',', '.'));

  Future<void> _trade() async {
    if (_busy) return;
    final amount = _amount;
    if (amount == null || !amount.isFinite || amount < 5) {
      _showMessage('En az ₺5 tutarında geçerli sayı gir.');
      return;
    }
    if (!widget.quote.isFresh) {
      _showMessage('Bu fiyat güncel değil. Ana ekranda yenileme yap.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_side == TradeSide.buy ? 'Sanal alış' : 'Sanal satış'),
        content: Text(
          '${widget.quote.symbol} için ${formatTry(amount)} tutarında ' 
          '${_side == TradeSide.buy ? 'alış' : 'satış'} emri verilsin mi?\n\n' 
          'Bu işlem gerçek borsaya gönderilmez.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Onayla')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.placeOrder(
        quote: widget.quote,
        side: _side,
        amountTry: amount,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TradeException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('İşlem kaydedilemedi: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final holding = widget.portfolio.holdings[quote.id];
    final maxSellGross = (holding?.quantity ?? 0) * quote.priceTry;
    final amount = _amount;
    final grossBuy = amount == null ? 0.0 : amount / (1 + tradingFeeRate);
    final fee = amount == null ? 0.0 :
      _side == TradeSide.buy ? amount - grossBuy : amount * tradingFeeRate;
    final estimatedQty = amount == null ? 0.0 :
      (_side == TradeSide.buy ? grossBuy : amount) / quote.priceTry;
    final accent = quote.change24h >= 0 ? PremiumColors.emerald : PremiumColors.danger;

    return Scaffold(
      appBar: AppBar(title: Text('${quote.symbol} / TRY')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(quote.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(formatCoinPriceTry(quote.priceTry), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${formatChange(quote.change24h)} (24s)', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PremiumColors.panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: PremiumColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Son 7 gün · fiyat eğilimi', style: TextStyle(color: PremiumColors.gold, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              MiniChart(prices: quote.sparkline, positive: quote.change24h >= 0, height: 150),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => ExpertAnalysisScreen(quote: quote),
            )),
            icon: const Icon(Icons.query_stats),
            label: const Text('Botun teknik analizini gör'),
          ),
          const SizedBox(height: 20),
          Text('Yerel sanal SPOT işlemi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          const Text('Buradaki AL/SAT yalnızca tarayıcıdaki yerel kasayı '
              'etkiler. 1x SHORT işlemleri ayrı sunucu botunda görüntülenir.',
            style: TextStyle(fontSize: 11, color: PremiumColors.muted)),
          const SizedBox(height: 12),
          SegmentedButton<TradeSide>(
            segments: const [
              ButtonSegment(value: TradeSide.buy, label: Text('AL'), icon: Icon(Icons.add_circle_outline)),
              ButtonSegment(value: TradeSide.sell, label: Text('SAT'), icon: Icon(Icons.remove_circle_outline)),
            ],
            selected: {_side},
            onSelectionChanged: (selection) => setState(() => _side = selection.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            decoration: InputDecoration(
              labelText: 'İşlem tutarı (₺)',
              hintText: 'Örn. 100',
              border: const OutlineInputBorder(),
              suffixIcon: TextButton(
                onPressed: () {
                  final max = _side == TradeSide.buy ? widget.portfolio.cashTry : maxSellGross;
                  _amountController.text = (math.max(0.0, (max * 100).floor() / 100)).toStringAsFixed(2);
                  setState(() {});
                },
                child: const Text('MAX'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _valueRow('Tahmini miktar', '${formatQuantity(estimatedQty)} ${quote.symbol}'),
          _valueRow('Komisyon (%0,1)', formatTry(fee)),
          _valueRow('Sanal TL bakiyesi', formatTry(widget.portfolio.cashTry)),
          _valueRow('Coin bakiyesi', '${formatQuantity(holding?.quantity ?? 0)} ${quote.symbol}'),
          const SizedBox(height: 14),
          if (!quote.isFresh)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Fiyat eskidi; yeni işlem için piyasa ekranını yenile.', style: TextStyle(color: Colors.orangeAccent)),
            ),
          FilledButton.icon(
            onPressed: _busy || !quote.isFresh ? null : _trade,
            icon: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.swap_horiz),
            label: Text(_busy ? 'Kaydediliyor...' : _side == TradeSide.buy ? 'SANAL AL' : 'SANAL SAT'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 12),
          const Text('Demo işlemidir. Fiyat CoinGecko piyasa verisinden gelir; komisyon simülasyondur. Gerçek emir, yatırım veya para transferi yoktur.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _valueRow(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(color: Colors.white60))),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}
