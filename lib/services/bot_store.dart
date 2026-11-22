import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'learning_bot.dart';

/// Browser-local settings and online-learning history.
/// Never contains API secrets or real exchange credentials.
class BotStore {
  BotStore({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'sanal_trader_learning_bot_v1';
  final SharedPreferencesAsync _prefs;

  Future<BotState> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return BotState.initial();
    try {
      return BotState.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // Do not allow a corrupted record to accidentally enable the trader.
      return BotState.initial();
    }
  }

  Future<void> save(BotState state) async {
    await _prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> clear() => _prefs.remove(_key);
}
