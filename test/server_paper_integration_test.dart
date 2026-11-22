import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/server_paper_card.dart';
import 'package:sanal_trader/widgets/server_paper_overview.dart';

Map<String, dynamic> paperState({
  bool withShort = false,
  bool withTrades = true,
}) => {
  'schema': 1,
  'enabled': true,
  'cashTry': withShort ? 580.0 : 571.922,
  'initialCashTry': 650,
  'equityTry': 649.922,
  'realizedTry': -0.078,
  'paidFeesTry': .078,
  'lastSuccessAt': DateTime.now().toUtc().toIso8601String(),
  'lastDecision': 'Güncel piyasa verisi incelendi.',
  'holdings': {
    'NEARUSDT': {'quantity': 2.0, 'costTry': 78.0},
  },
  'shorts': withShort ? {
    'ADAUSDT': {
      'quantity': 6.0,
      'marginTry': 40.0,
      'entryPriceTry': 7.0,
    }
  } : {},
  'marksTry': withShort ? {'ADAUSDT': 6.5} : {},
  'trades': withTrades ? [
    {
      'at': '2026-11-22T18:00:00Z',
      'side': 'buy', 'symbol': 'NEARUSDT',
      'grossTry': 78.0, 'feeTry': 0.078,
      'reason': 'Trend onayı', 'realizedPnlTry': 0,
    },
    if (withShort) {
      'at': '2026-11-22T18:05:00Z',
      'side': 'short', 'symbol': 'ADAUSDT',
      'grossTry': 40.0, 'feeTry': .040,
      'reason': 'Düşüş onayı', 'realizedPnlTry': 0,
    },
  ] : [],
};

void main() {
  test('Server snapshot parses separate long, short, and cash fields', () {
    final snapshot = ServerPaperSnapshot.fromJson(
      paperState(withShort: true));
    expect(snapshot.cashTry, 580);
    expect(snapshot.holdings.keys, contains('NEARUSDT'));
    expect(snapshot.shorts.keys, contains('ADAUSDT'));
    expect(snapshot.trades.length, 2);
    expect(snapshot.pnlTry, closeTo(-.078, .00001));
    expect(snapshot.isHealthyAt(DateTime.now()), isTrue);
    expect(snapshot.startingTry, 650);
  });

  test('Existing paper data without shorts remains readable', () {
    final old = paperState()..remove('shorts');
    final snapshot = ServerPaperSnapshot.fromJson(old);
    expect(snapshot.shorts, isEmpty);
    expect(snapshot.holdings.length, 1);
  });

  test('Damaged or negative server state is rejected, not shown as zero', () {
    expect(
      () => ServerPaperSnapshot.fromJson({
        ...paperState(), 'equityTry': -200,
      }),
      throwsFormatException);
    expect(
      () => ServerPaperSnapshot.fromJson({
        ...paperState(), 'schema': 99,
      }),
      throwsFormatException);
  });

  test('Last real schedule status is optional and never faked', () {
    final original = ServerPaperSnapshot.fromJson(paperState());
    expect(original.lastScheduledTriggerAt, isNull);
    expect(original.lastTriggerEvent, isNull);

    final pushed = paperState();
    pushed['lastTriggerEvent'] = 'push';
    pushed['lastTriggerAt'] = '2026-11-22T20:30:00Z';
    var snapshot = ServerPaperSnapshot.fromJson(pushed);
    expect(snapshot.lastTriggerEvent, 'push');
    expect(snapshot.lastScheduledTriggerAt, isNull);

    pushed['lastScheduledTriggerAt'] = '2026-11-22T20:35:00Z';
    pushed['lastTriggerEvent'] = 'schedule';
    snapshot = ServerPaperSnapshot.fromJson(pushed);
    expect(snapshot.lastScheduledTriggerAt, DateTime.utc(2026, 11, 22, 20, 35));
    expect(snapshot.lastTriggerEvent, 'schedule');
  });

  testWidgets('Server panel reports missing cron truthfully', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = paperState();
    state['lastTriggerEvent'] = 'push';
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerPaperCard(
        snapshot: ServerPaperSnapshot.fromJson(state),
        loading: false, error: null,
        onRefresh: () {}, onOpenTrades: () {},
      )),
    )));
    expect(find.textContaining('henüz doğrulanmadı'), findsOneWidget);
    expect(find.textContaining('kod güncellemesi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Real equity observations stay separate from browser demo', () {
    final state = paperState();
    expect(ServerPaperSnapshot.fromJson(state).equityHistory, isEmpty);
    state['equityHistory'] = [
      {'at': '2026-11-22T20:00:00Z', 'equityTry': 650.0},
      {'at': '2026-11-22T20:05:00Z', 'equityTry': 649.922},
    ];
    final s = ServerPaperSnapshot.fromJson(state);
    expect(s.equityHistory.length, 2);
    expect(s.equityHistory.last['equityTry'], 649.922);
  });

  testWidgets('Autonomous main card shows real server wallet and working links',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1450);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = paperState();
    state['equityHistory'] = [
      {'at': '2026-11-22T20:00:00Z', 'equityTry': 650.0},
      {'at': '2026-11-22T20:05:00Z', 'equityTry': 649.922},
    ];
    var botOpened = false;
    var tradesOpened = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerPaperOverview(
        snapshot: ServerPaperSnapshot.fromJson(state),
        loading: false, error: null,
        onRefresh: () {},
        onOpenBot: () => botOpened = true,
        onOpenTrades: () => tradesOpened = true,
      )),
    )));
    expect(find.text('OTONOM BOT · ANA SANAL KASA'), findsOneWidget);
    expect(find.textContaining('Son sanal işlem: NEARUSDT · Spot AL'),
      findsOneWidget);
    expect(find.text('GERÇEK SANAL KASA EĞRİSİ'), findsOneWidget);
    await tester.tap(find.text('Bot merkezi'));
    await tester.tap(find.text('İşlemler'));
    expect(botOpened, isTrue);
    expect(tradesOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Server portfolio only shows real server positions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ServerPaperPositionsPanel(
        snapshot: ServerPaperSnapshot.fromJson(paperState()),
        onOpenTrades: () {},
      ),
    )));
    expect(find.text('ANA SUNUCU PORTFÖYÜ'), findsOneWidget);
    expect(find.text('SPOT · NEARUSDT'), findsOneWidget);
    expect(find.text('Güncel fiyat yok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Server status detects stale data and errors', () {
    final state = paperState();
    state['lastSuccessAt'] =
        DateTime.now().toUtc().subtract(
          const Duration(minutes: 40)).toIso8601String();
    expect(ServerPaperSnapshot.fromJson(state)
        .isHealthyAt(DateTime.now()), isFalse);
    state['lastSuccessAt'] = DateTime.now().toUtc().toIso8601String();
    state['lastError'] = 'provider outage';
    expect(ServerPaperSnapshot.fromJson(state)
        .isHealthyAt(DateTime.now()), isFalse);
  });

  test('Server public GET parses live data, never performs a POST', () async {
    var requests = 0;
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers.containsKey('cache-control'), isFalse);
      expect(request.url.host, 'raw.githubusercontent.com');
      requests++;
      return http.Response.bytes(
        utf8.encode(jsonEncode(paperState(withShort: true))), 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repo = ServerPaperRepository(client: client);
    final state = await repo.load();
    expect(state.shorts.keys, contains('ADAUSDT'));
    expect(requests, 1);
    repo.dispose();
  });

  test('HTTP failure stays an error rather than a fake 650 TL reset', () async {
    final repo = ServerPaperRepository(
      client: MockClient((request) async =>
          http.Response('not available', 503)),
    );
    await expectLater(repo.load(), throwsException);
    repo.dispose();
  });

  testWidgets('Panel server tile navigates to bot, not local wallet',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ServerPaperSummaryTile(
        snapshot: ServerPaperSnapshot.fromJson(paperState()),
        loading: false, error: null,
        onTap: () => opened = true,
      )),
    ));
    expect(find.text('ANA SANAL KASA · SUNUCU BOTU'), findsOneWidget);
    await tester.tap(find.text('ANA SANAL KASA · SUNUCU BOTU'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Server card shows LONG and SHORT independently', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var clicked = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerPaperCard(
        snapshot: ServerPaperSnapshot.fromJson(paperState(withShort: true)),
        loading: false, error: null,
        onRefresh: () {},
        onOpenTrades: () => clicked = true,
      )),
    )));
    expect(find.textContaining('Açık SPOT'), findsOneWidget);
    expect(find.textContaining('Açık SHORT'), findsOneWidget);
    expect(find.textContaining('SHORT ADAUSDT'), findsOneWidget);
    await tester.ensureVisible(
      find.text('Sunucu işlemleri ve hesap geçmişi'));
    await tester.tap(find.text('Sunucu işlemleri ve hesap geçmişi'));
    expect(clicked, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Server decision plan survives JSON parsing and legacy migration', () {
    final source = paperState();
    source['decisionPlan'] = {
      'action': 'SHORT',
      'marketRegime': 'DÜŞÜŞ',
      'symbol': 'ADAUSDT',
      'reason': 'Düşüş teyidi',
      'reviewed': 12,
      'amountTry': 70,
      'candidates': [
        {'symbol': 'ADAUSDT', 'action': 'SHORT', 'score': 0.9},
      ],
    };
    final snapshot = ServerPaperSnapshot.fromJson(source);
    expect(snapshot.decisionPlan['action'], 'SHORT');
    expect(snapshot.decisionPlan['marketRegime'], 'DÜŞÜŞ');
    final older = ServerPaperSnapshot.fromJson(paperState());
    expect(older.decisionPlan, isEmpty);
  });

  testWidgets('Decision center expands and explains autonomous SHORT logic',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = paperState(withShort: true);
    state['decisionPlan'] = {
      'action': 'SHORT',
      'marketRegime': 'DÜŞÜŞ',
      'symbol': 'ADAUSDT',
      'reason': 'Piyasa düşüyor, sanal 1x SHORT sinyali uygun',
      'reviewed': 12,
      'amountTry': 50.0,
      'score': .91,
      'candidates': [
        {'symbol': 'ADAUSDT', 'action': 'SHORT', 'score': .91},
      ],
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: ServerPaperCard(
        snapshot: ServerPaperSnapshot.fromJson(state),
        loading: false, error: null,
        onRefresh: () {}, onOpenTrades: () {},
      )),
    )));
    expect(find.text('Otonom Karar Merkezi'), findsOneWidget);
    expect(find.textContaining('1x SHORT AÇ'), findsOneWidget);
    await tester.ensureVisible(find.text('Otonom Karar Merkezi'));
    await tester.tap(find.text('Otonom Karar Merkezi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Piyasa düşüyor'), findsOneWidget);
    expect(find.textContaining('ADAUSDT · SHORT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Open history page refreshes when shared server data changes',
      (tester) async {
    final live = ValueNotifier<ServerPaperSnapshot?>(
      ServerPaperSnapshot.fromJson(paperState()));
    addTearDown(live.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ServerPaperTradesScreen(snapshots: live, onRefresh: () {}),
    ));
    expect(find.textContaining('SPOT AL · NEARUSDT'), findsOneWidget);
    live.value = ServerPaperSnapshot.fromJson(
      paperState(withShort: true));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('SHORT AÇ · ADAUSDT'), 150,
    );
    expect(find.textContaining('SHORT AÇ · ADAUSDT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
