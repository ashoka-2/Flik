import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/history_entry.dart';

// Manages local preferences, device identity, paired tokens, and transfer history.
class StorageService {
  static const _keyDeviceId = 'flik_device_id';
  static const _keyDeviceName = 'flik_device_name';
  static const _keyTokens = 'flik_paired_tokens';
  static const _keyHistory = 'flik_transfer_history';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String getDeviceId() {
    var id = _prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  String getDeviceName() {
    return _prefs.getString(_keyDeviceName) ?? 'Android Phone';
  }

  Future<void> setDeviceName(String name) async {
    await _prefs.setString(_keyDeviceName, name.trim());
  }

  String? getToken(String peerDeviceId) {
    final raw = _prefs.getString(_keyTokens);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[peerDeviceId] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String peerDeviceId, String token) async {
    final raw = _prefs.getString(_keyTokens);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    map[peerDeviceId] = token;
    await _prefs.setString(_keyTokens, jsonEncode(map));
  }

  Future<void> removeToken(String peerDeviceId) async {
    final raw = _prefs.getString(_keyTokens);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.remove(peerDeviceId);
      await _prefs.setString(_keyTokens, jsonEncode(map));
    } catch (_) {}
  }

  List<TransferHistoryEntry> getHistory() {
    final raw = _prefs.getStringList(_keyHistory);
    if (raw == null) return [];
    return raw.map((e) {
      try {
        return TransferHistoryEntry.fromJson(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<TransferHistoryEntry>().toList();
  }

  Future<void> addHistoryEntry(TransferHistoryEntry entry) async {
    final list = getHistory();
    list.insert(0, entry);
    // Keep max 50 entries
    final trimmed = list.take(50).toList();
    final jsonList = trimmed.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_keyHistory, jsonList);
  }
}
