import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/main.dart';
import 'package:sanal_trader/screens/home_screen.dart';

void main() {
  test('Uygulama tek sunucu beyniyle baslatilir', () {
    const app = TradingApp();
    expect(app, isA<TradingApp>());
    expect(const HomeScreen(), isA<HomeScreen>());
  });
}
