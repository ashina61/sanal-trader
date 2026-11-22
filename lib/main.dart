import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'widgets/premium_dashboard.dart';
import 'services/cloud_portfolio_repository.dart';
import 'services/local_portfolio_repository.dart';
import 'services/portfolio_repository.dart';

const _enableFirebase = bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final PortfolioRepository repo = _enableFirebase
        ? await CloudPortfolioRepository.create()
        : LocalPortfolioRepository();
    runApp(TradingApp(repository: repo, cloudMode: _enableFirebase));
  } catch (error) {
    // Firebase yapılandırması başarısızsa yerel kayıtla karıştırma.
    runApp(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Firebase bağlantı hatası')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText('Firebase başlatılamadı:\n\n$error\n\n'
              'Önce flutterfire configure --platforms=android çalıştır, '
              'Authentication > Anonymous ve Cloud Firestore özelliklerini etkinleştir. '
              'Veya --dart-define=ENABLE_FIREBASE=true parametresini kaldırıp yerel modda başlat.'),
        ),
      ),
    ));
  }
}

class TradingApp extends StatelessWidget {
  const TradingApp({super.key, required this.repository, required this.cloudMode});
  final PortfolioRepository repository;
  final bool cloudMode;

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
      home: HomeScreen(repository: repository, cloudMode: cloudMode),
    );
  }
}
