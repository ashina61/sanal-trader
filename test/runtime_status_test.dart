import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/services/server_paper_repository.dart';
import 'package:sanal_trader/widgets/server_runtime_status.dart';

final observed = DateTime.utc(2026, 11, 23, 18);

Map<String, dynamic> snapshot({String phase = 'COMPLETE'}) => {
  'schema': 1, 'enabled': true, 'cashTry': 600, 'equityTry': 650,
  'initialCashTry': 650, 'holdings': <String, dynamic>{}, 'trades': [],
  'lastSuccessAt': observed.toIso8601String(), 'tracked': 250,
  'decisionPlan': {'action': 'WAIT', 'reason': 'Onaylı giriş yok'},
  'runtimeStatus': {
    'schema': 1, 'phase': phase, 'reason': 'Onaylı giriş yok',
    'marketObservedAt': observed.toIso8601String(),
    'oldestQuoteAt': observed.toIso8601String(),
    'exitCheckedAt': observed.toIso8601String(),
    'positionsChecked': 2, 'exitOrders': 0, 'cycleElapsedSec': 9.5,
    'shortlisted': 51, 'scanCompleted': true,
    'scanCoverage': {'minute1m': {'requested': 51, 'valid': 50, 'failed': 1}},
  },
};

void main() {
  test('Stale data and partial scans cannot report healthy', () {
    final complete = ServerPaperSnapshot.fromJson(snapshot());
    expect(complete.isHealthyAt(observed.add(const Duration(minutes: 2))), isTrue);
    final delayed = observed.add(const Duration(minutes: 5));
    expect(complete.isHealthyAt(delayed), isFalse);
    expect(complete.runtimeLabelAt(delayed), 'Piyasa kontrolü gecikti');
    final partial = ServerPaperSnapshot.fromJson(snapshot(phase: 'DEGRADED'));
    expect(partial.isHealthyAt(observed), isFalse);
    expect(partial.runtimeLabelAt(observed), contains('kısmi mum verisi'));
    final failed = ServerPaperSnapshot.fromJson(snapshot(phase: 'ERROR'));
    expect(failed.isHealthyAt(observed), isFalse);
    expect(failed.runtimeLabelAt(observed), 'Kontrol tamamlanamadı');
  });

  test('Old states remain readable without invented runtime diagnostics', () {
    final old = snapshot()..remove('runtimeStatus');
    final state = ServerPaperSnapshot.fromJson(old);
    expect(state.runtimeStatus, isEmpty);
    expect(state.runtimeDate('marketObservedAt'), isNull);
    expect(state.runtimeLabelAt(observed), 'Ayrıntılı durum kaydı bekleniyor');
  });

  test('An old exchange timestamp overrides a recent successful run', () {
    final data = snapshot();
    (data['runtimeStatus'] as Map)['oldestQuoteAt'] =
      observed.subtract(const Duration(minutes: 6)).toIso8601String();
    final state = ServerPaperSnapshot.fromJson(data);
    expect(state.isHealthyAt(observed), isFalse);
    expect(state.runtimeLabelAt(observed), 'Piyasa verisi eski');
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('Runtime panel fits ${width.toInt()}px with large text', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: Size(width, 1000),
          textScaler: const TextScaler.linear(1.3)),
        child: Scaffold(body: SingleChildScrollView(
          child: ServerRuntimeStatusCard(
            snapshot: ServerPaperSnapshot.fromJson(snapshot(phase: 'DEGRADED')),
            detailed: true, now: observed),
        )),
      )));
      expect(find.text('Kontrol tamamlandı · kısmi mum verisi'), findsOneWidget);
      expect(find.text('1 dakika: 50/51 başarılı · 1 eksik'), findsOneWidget);
      expect(find.text('2 pozisyon · 0 çıkış'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Read errors stay visible while cached wallet is displayed', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ServerRuntimeStatusCard(
        snapshot: ServerPaperSnapshot.fromJson(snapshot()), now: observed,
        error: 'Bağlantı zaman aşımına uğradı'),
    )));
    expect(find.text('Panel verisi yenilenemedi'), findsOneWidget);
    expect(find.text('Bağlantı zaman aşımına uğradı'), findsOneWidget);
    expect(find.textContaining('fırsat bekleniyor'), findsNothing);
  });
}
