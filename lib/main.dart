import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'widgets/premium_theme.dart';

/// One autonomous brain, one server-side 650 TRY paper wallet.
/// No local wallet or browser-bound bot is created by the live application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TradingApp());
}

class TradingApp extends StatelessWidget {
  const TradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = PremiumColors.gold;
    return MaterialApp(
      title: 'SanalTrader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: PremiumColors.gold,
          secondary: PremiumColors.emerald,
          surface: PremiumColors.panel,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: PremiumColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: PremiumColors.background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: PremiumColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: PremiumColors.border, width: .7),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: PremiumColors.panel,
          hintStyle: const TextStyle(color: PremiumColors.muted, fontSize: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: PremiumColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: PremiumColors.gold, width: 1.2),
          ),
        ),
        dividerColor: PremiumColors.border,
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: PremiumColors.background,
          indicatorColor: PremiumColors.goldDim,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
