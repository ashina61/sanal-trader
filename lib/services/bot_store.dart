import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'learning_bot.dart';

/// Persist local paper trading state. Autostart v2 is a one-time user request;
/// after that, the ON/OFF switch and reset persist without forced re-enabling.
class BotStore {
  BotStore({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();
  static const _key = 'sanal_trader_learning_bot_v2';
  static const _previous = 'sanal_trader_learning_bot_v1';
  final SharedPreferencesAsync _prefs;

  Future<BotState> load() async {
    final raw = await _prefs.getString(_key);
    if (raw != null) {
      try {
        return BotState.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        return BotState.initial(); // Corrupt data must NOT trigger orders.
      }
    }
    final old = await _prefs.getString(_previous);
    BotState state;
    if (old != null) {
      try {
        state = BotState.fromJson(Map<String, dynamic>.from(jsonDecode(old) as Map))
            ; // Preserve previous ON/OFF preference on migration.
      } catch (_) {
        state = BotState.initial(); // Do not enable corrupt migrated state.
      }
    } else {
      state = BotState.initial(); // Explicit opt-in, never two bots by default.
    }
    await save(state);
    return state;
  }

  Future<void> save(BotState state) =>
      _prefs.setString(_key, jsonEncode(state.toJson()));

  Future<void> clear() async {
    await _prefs.remove(_previous);
    await save(BotState.initial()); // Reset leaves the auto-bot disabled.
  }
}
