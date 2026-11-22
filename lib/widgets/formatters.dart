import 'package:intl/intl.dart';

final _tryFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
final _quantityFormat = NumberFormat.decimalPatternDigits(locale: 'tr_TR', decimalDigits: 8);

String formatTry(double value) => _tryFormat.format(value);
String formatQuantity(double value) => _quantityFormat.format(value);
String formatChange(double value) => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
