import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/formatters.dart';
import 'package:sanal_trader/widgets/server_paper_overview.dart';

Map<String, dynamic> wallet() => {
  'schema': 1, 'enabled': true, 'cashTry': 600,
  'equityTry': 650.5, 'netLiquidationTry': 649.5,
  'initialCashTry': 650, 'holdings': <String, dynamic>{}, 'trades': [],
};

void main() {
  test('Wallet growth includes estimated exit fees instead of gross marks', () {
    final state = ServerPaperSnapshot.fromJson(wallet());
    expect(state.markEquityTry, 650.5);
    expect(state.equityTry, 649.5);
    expect(state.pnlTry, -.5);
    expect(state.hasNetLiquidation, isTrue);
    final old = ServerPaperSnapshot.fromJson(wallet()..remove('netLiquidationTry'));
    expect(old.equityTry, 650.5);
    expect(old.hasNetLiquidation, isFalse);
  });

  test('Invalid net value cannot silently become a gross profit', () {
    expect(() => ServerPaperSnapshot.fromJson({...wallet(), 'netLiquidationTry': double.nan}),
      throwsFormatException);
  });

  testWidgets('Main balance displays the fee-inclusive value', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerPaperOverview(
        snapshot: ServerPaperSnapshot.fromJson(wallet()), loading: false,
        error: null, onOpenBot: () {}, onOpenTrades: () {}, onRefresh: () {},
      )),
    )));
    expect(find.text(formatTry(649.5)), findsOneWidget);
    expect(find.text(formatTry(650.5)), findsNothing);
    expect(find.text('Tahmini kapanış komisyonu dahil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
