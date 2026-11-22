import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanal_trader/models/portfolio.dart';
import 'package:sanal_trader/services/learning_bot.dart';
import 'package:sanal_trader/screens/market_radar_screen.dart';
import 'package:sanal_trader/screens/bot_performance_screen.dart';

void main() {
  testWidgets('Radar is searchable with no prices and does not fake candidates',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: MarketRadarScreen(quotes: const {}, onOpen: (_) {}),
    )));
    expect(find.text('Piyasa Radarı'), findsOneWidget);
    expect(find.textContaining('0 güncel coin'), findsOneWidget);
    expect(find.text('Bu filtrede güncel veri yok.'), findsOneWidget);
  });

  testWidgets('Profit dashboard distinguishes unrealized and closed trade data',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: BotPerformanceScreen(
        wallet: Portfolio.fresh(), quotes: const {},
        bot: BotState.initial(), onViewTrades: () {},
        serverSnapshot: null,
        serverBusy: false,
        serverError: null,
        onViewServerTrades: () {},
      ),
    )));
    expect(find.text('Performans Merkezi'), findsOneWidget);
    expect(find.text('Kapanan bot satışları'), findsOneWidget);
    final emptyState = find.textContaining('Bot henüz sanal satış kapatmadı');
    // The performance page is a lazy scrolling ListView: the section is
    // intentionally below the fold on compact mobile screens.
    await tester.scrollUntilVisible(
      emptyState, 180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(emptyState, findsOneWidget);
    expect(find.textContaining('%100 başarı'), findsNothing);
  });
}
