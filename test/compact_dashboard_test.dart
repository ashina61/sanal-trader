import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/compact_wallet_card.dart';
import 'package:sanal_trader/widgets/execution_pipeline_card.dart';

void main() {
  final state = ServerPaperSnapshot.fromJson({
    'schema': 1,
    'cashTry': 210.5,
    'initialCashTry': 650.0,
    'equityTry': 648.5,
    'netLiquidationTry': 648.0,
    'holdings': <String, dynamic>{},
    'shorts': <String, dynamic>{},
    'trades': <Map<String, dynamic>>[],
    'enabled': true,
    'decisionPlan': {
      'action': 'WAIT',
      'at': '2026-11-23T20:30:00Z',
      'executionPipeline': {
        'status': 'BLOCKED',
        'reason': 'Emir defteri makası yüksek',
        'symbol': 'SOLUSDT',
        'bookObserved': true,
        'spreadPct': 1.2,
        'stages': [
          for (final name in ['PULSE','IMPACT','EDGE','SIZE','ENTRY','EXIT'])
            {'name': name, 'status': name == 'PULSE'
                ? 'BLOCKED' : 'SKIPPED', 'detail': '$name kanıtı'},
        ],
      },
    },
  });

  testWidgets('compact net wallet fits narrow Android layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CompactWalletCard(
          snapshot: state, onTrades: () {}, onRefresh: () {})),
    )));
    expect(find.text('TEK SANAL KASA'), findsOneWidget);
    expect(find.text('Nakit'), findsOneWidget);
    expect(find.text('Pozisyon'), findsOneWidget);
    expect(find.text('İşlem'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('six stages show concise status and expandable evidence',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ExecutionPipelineCard(snapshot: state)),
    )));
    expect(find.text('6 Aşamalı Karar Motoru'), findsOneWidget);
    expect(find.text('PULSE'), findsOneWidget);
    expect(find.text('EXIT'), findsOneWidget);
    expect(find.text('RET'), findsOneWidget);
    await tester.tap(find.text('Karar aşamaları ve maliyetler'));
    await tester.pumpAndSettle();
    expect(find.text('PULSE kanıtı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
