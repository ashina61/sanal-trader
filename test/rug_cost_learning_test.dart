import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/free_dex_radar_card.dart';
import 'package:sanal_trader/widgets/trade_learning_card.dart';

void main() {
  final snapshot = ServerPaperSnapshot.fromJson({
    'schema': 1,
    'cashTry': 220.0,
    'equityTry': 645.0,
    'netLiquidationTry': 644.7,
    'initialCashTry': 650.0,
    'holdings': <String, dynamic>{},
    'shorts': <String, dynamic>{},
    'trades': <Map<String, dynamic>>[],
    'objective': {
      'scenarioNetAfterSlippageTry': 644.4,
    },
    'tradeLearning': {
      'status': 'OBSERVING',
      'recentLossStreak': 2,
      'recent10': {
        'netRealizedTry': -1.25,
        'avgNetPerCloseTry': -0.125,
      },
      'closed': {
        'closed': 10,
        'profitFactor': 0.85,
      },
      'byExit': {
        'STOP': {'closed': 3, 'netRealizedTry': -5.1},
        'TAKE_PROFIT': {'closed': 4, 'netRealizedTry': 3.9},
      }
    },
    'freeDexRadar': {
      'status': 'OBSERVING', 'poolsScreened': 1,
      'tradesChecked': 3, 'observedSenders': 3,
      'walletsObserved': <Map<String, dynamic>>[],
      'history': <Map<String, dynamic>>[],
      'tokenRisk': {
        'checked': 1, 'riskFlagged': 1, 'unknown': 0,
        'results': [
          {
            'chain': 'base', 'symbol': 'DANGER',
            'status': 'RISK_FLAGGED',
            'flags': ['Olası honeypot', 'Yeni token basma yetkisi'],
          }
        ],
      },
    },
  });

  testWidgets('profit learning audit is compact on 320px screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: TradeLearningCard(snapshot: snapshot)))));
    expect(find.text('İşlemlerden Öğrenme'), findsOneWidget);
    expect(find.text('Kayıp serisi'), findsOneWidget);
    expect(find.textContaining('5 baz puan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Çıkış türüne göre net sonuç'));
    await tester.tap(find.text('Çıkış türüne göre net sonuç'));
    await tester.pumpAndSettle();
    expect(find.text('STOP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('token risk research stays visible without safe label',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: FreeDexRadarCard(snapshot: snapshot)))));
    expect(find.text('Ücretsiz DEX Keşfi'), findsOneWidget);
    await tester.ensureVisible(find.text('Token sözleşmesi · Risk kontrolü'));
    await tester.tap(find.text('Token sözleşmesi · Risk kontrolü'));
    await tester.pumpAndSettle();
    expect(find.text('RİSK UYARISI'), findsOneWidget);
    expect(find.textContaining('honeypot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
