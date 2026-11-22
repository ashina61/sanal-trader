import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/coin_quote.dart';
import '../models/portfolio.dart';
import 'portfolio_repository.dart';
import 'trade_engine.dart';

/// `flutterfire configure --platforms=android` tamamlandıktan sonra kullanılabilir.
/// Android, google-services.json / Android kaynaklarından varsayılan app'i alır.
class CloudPortfolioRepository implements PortfolioRepository {
  CloudPortfolioRepository._(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;

  static Future<CloudPortfolioRepository> create() async {
    await Firebase.initializeApp();
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Anonim Firebase oturumu açılamadı.');
    final repo = CloudPortfolioRepository._(FirebaseFirestore.instance, user.uid);
    final current = await repo._wallet.get();
    if (!current.exists) await repo._wallet.set(Portfolio.fresh().toJson());
    return repo;
  }

  DocumentReference<Map<String, dynamic>> get _wallet =>
      _db.collection('users').doc(_uid).collection('wallet').doc('main');

  CollectionReference<Map<String, dynamic>> get _trades =>
      _db.collection('users').doc(_uid).collection('trades');

  @override
  Future<Portfolio> load() async {
    final walletDoc = await _wallet.get();
    final tradeDocs = await _trades.orderBy('executedAt', descending: true).limit(300).get();
    final trades = tradeDocs.docs.map((doc) => TradeRecord.fromJson(doc.data())).toList();
    return Portfolio.fromJson(walletDoc.data() ?? Portfolio.fresh().toJson(), trades: trades);
  }

  @override
  Future<Portfolio> placeOrder({
    required CoinQuote quote,
    required TradeSide side,
    required double amountTry,
  }) async {
    // Aynı kullanıcı iki cihazda işlem yapsa da bakiye güncellemesi atomiktir.
    final tradeRef = _trades.doc();
    await _db.runTransaction((transaction) async {
      final walletSnap = await transaction.get(_wallet);
      final current = Portfolio.fromJson(
        walletSnap.data() ?? Portfolio.fresh().toJson(),
      );
      final result = executeVirtualTrade(
        current: current,
        quote: quote,
        side: side,
        amountTry: amountTry,
        tradeId: tradeRef.id,
      );
      transaction.set(_wallet, result.portfolio.toJson());
      transaction.set(tradeRef, result.trade.toJson());
    });
    return load();
  }

  @override
  Future<void> reset() async {
    final docs = await _trades.get();
    for (var start = 0; start < docs.docs.length; start += 450) {
      final batch = _db.batch();
      for (final doc in docs.docs.skip(start).take(450)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _wallet.set(Portfolio.fresh().toJson());
  }
}
