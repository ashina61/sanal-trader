import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/learning_bot.dart';
import 'package:sanal_trader/widgets/premium_dashboard.dart';

void main() {
  testWidgets('Premium portfolio shows the real 650 TL paper balance on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: PremiumPortfolioCard(
          wallet: Portfolio.fresh(),
          quotes: const {},
          cloudMode: false,
        ),
      )),
    ));
    expect(find.text('YEREL SANAL PORTFÖY'), findsOneWidget);
    expect(find.textContaining('650'), findsWidgets);
    expect(find.textContaining('1.248.730'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bot card shows measured state, not a fabricated AI score',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: PremiumBotOverview(
          bot: BotState.initial(),
          btc: null,
          onTap: () => tapped = true,
        ),
      )),
    ));
    expect(find.text('Ölçülmedi'), findsOneWidget);
    expect(find.text('Veri bekleniyor'), findsOneWidget);
    expect(find.text('%78'), findsNothing);
    await tester.tap(find.text('Bot kapalı · detayları aç'));
    expect(tapped, isTrue);
  });

  testWidgets('Premium history tile uses a functional callback',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PremiumUpdateTile(
        version: '0.5.0',
        onTap: () => opened = true,
      )),
    ));
    expect(find.text('Güncelleme Geçmişi'), findsOneWidget);
    await tester.tap(find.text('Güncelleme Geçmişi'));
    expect(opened, isTrue);
  });
}
