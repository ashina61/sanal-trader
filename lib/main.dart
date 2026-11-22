import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
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
    const accent = Color(0xFF43D9A3);
    return MaterialApp(
      title: 'SanalTrader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF101720),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF101720)),
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      home: HomeScreen(repository: repository, cloudMode: cloudMode),
    );
  }
}
