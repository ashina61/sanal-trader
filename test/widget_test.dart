import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/main.dart';
import 'package:sanal_trader/services/local_portfolio_repository.dart';

void main() {
  test('Uygulama widget başlangıcı oluşturulabilir', () {
    final app = TradingApp(
      repository: LocalPortfolioRepository(),
      cloudMode: false,
    );
    expect(app.cloudMode, isFalse);
  });
}
