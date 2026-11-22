import 'package:intl/intl.dart';

final _tryFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
final _quantityFormat = NumberFormat.decimalPatternDigits(locale: 'tr_TR', decimalDigits: 8);

String formatTry(double value) => _tryFormat.format(value);
String formatQuantity(double value) => _quantityFormat.format(value);
String formatChange(double value) => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';

String formatCoinPriceTry(double value) {
  if (!value.isFinite || value < 0) return '—';
  if (value > 0 && value < 0.00000001) {
    return '₺' + value.toStringAsExponential(4);
  }
  final digits = value >= 1 ? 2
      : value >= 0.01 ? 4
      : value >= 0.0001 ? 6 : 8;
  return NumberFormat.currency(
    locale: 'tr_TR', symbol: '₺', decimalDigits: digits,
  ).format(value);
}
