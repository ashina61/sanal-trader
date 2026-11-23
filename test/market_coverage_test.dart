import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/server_runtime_status.dart';

void main() {
  testWidgets('Coverage distinguishes watched pairs from charts and raw quotes', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final now = DateTime.now().toUtc();
    final state = ServerPaperSnapshot.fromJson({
      'schema': 1, 'enabled': true, 'cashTry': 650, 'equityTry': 650,
      'initialCashTry': 650, 'holdings': <String, dynamic>{}, 'trades': [],
      'lastSuccessAt': now.toIso8601String(),
      'coverageStats': {
        'at': now.toIso8601String(), 'freshMarketPairs': 1311,
        'liquidPairs': 161, 'minuteObservedPairs': 96, 'minuteRequestedPairs': 96,
        'recentMinutePairs': 150, 'fullTechnicalPairs': 90,
        'liquidSymbols': ['BTCUSDT', 'ETHUSDT'],
      },
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerRuntimeStatusCard(
        snapshot: state, detailed: true, now: now)),
    )));
    expect(find.text('İzlenen likit parite'), findsOneWidget);
    expect(find.text('161'), findsOneWidget);
    expect(find.text('96 / 96 başarılı'), findsOneWidget);
    expect(find.text('150 / 161 parite'), findsOneWidget);
    expect(find.text('90 parite'), findsOneWidget);
    expect(find.textContaining('1311'), findsNothing);
    expect(find.text('İzlenen pariteler (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
