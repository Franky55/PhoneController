import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import '../services/ble_connection.dart';
import '../services/connection.dart';
import '../services/ws_connection.dart';

enum LogKind { tx, rx, info, error }

class LogEntry {
  LogEntry(this.kind, this.text, {this.stream = false}) : time = DateTime.now();
  final DateTime time;
  final LogKind kind;
  final String text;

  /// True for high-frequency joystick traffic (hidden in the console by default).
  final bool stream;
}

class AppState extends ChangeNotifier {
  static const _prefsProfiles = 'profiles';
  static const _prefsActive = 'activeProfile';
  static const _maxLog = 500;

  late SharedPreferences _prefs;
  List<Profile> profiles = [];
  String _activeId = '';

  DeviceConnection? _conn;
  final List<StreamSubscription> _connSubs = [];
  LinkState linkState = LinkState.disconnected;
  String? lastError;

  final List<LogEntry> log = [];
  String _rxBuffer = '';

  /// Runtime ON/OFF state of toggle controls, by control id.
  final Map<String, bool> toggleStates = {};

  /// Runtime value of slider controls, by control id.
  final Map<String, double> sliderValues = {};

  Profile get active => profiles.firstWhere((p) => p.id == _activeId, orElse: () => profiles.first);
  bool get isConnected => linkState == LinkState.connected;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_prefsProfiles);
    if (raw != null) {
      try {
        profiles = (jsonDecode(raw) as List).map((e) => Profile.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        debugPrint('Could not read saved profiles: $e');
      }
    }
    if (profiles.isEmpty) profiles = [Profile.rcCar()];
    _activeId = _prefs.getString(_prefsActive) ?? profiles.first.id;
    if (!profiles.any((p) => p.id == _activeId)) _activeId = profiles.first.id;
  }

  Future<void> _save() async {
    await _prefs.setString(_prefsProfiles, jsonEncode(profiles.map((p) => p.toJson()).toList()));
    await _prefs.setString(_prefsActive, _activeId);
  }

  // ---------------------------------------------------------------- profiles

  /// Mutate the active profile, then persist and refresh the UI.
  void updateActive(void Function(Profile p) change) {
    change(active);
    _save();
    notifyListeners();
  }

  Future<void> selectProfile(String id) async {
    if (id == _activeId) return;
    await disconnect();
    _activeId = id;
    toggleStates.clear();
    sliderValues.clear();
    _save();
    notifyListeners();
  }

  void addProfile(Profile p) {
    profiles.add(p);
    selectProfile(p.id);
  }

  void duplicateActive() {
    final copy = Profile.fromJson(jsonDecode(jsonEncode(active.toJson())))
      ..id = newId()
      ..name = '${active.name} (copy)';
    for (final c in copy.controls) {
      c.id = newId();
    }
    addProfile(copy);
  }

  void deleteActive() {
    if (profiles.length <= 1) return;
    final id = _activeId;
    selectProfile(profiles.firstWhere((p) => p.id != id).id);
    profiles.removeWhere((p) => p.id == id);
    _save();
    notifyListeners();
  }

  String exportActive() => const JsonEncoder.withIndent('  ').convert(active.toJson());

  /// Imports a profile from JSON text. A fresh id is assigned. Throws on bad input.
  void importProfile(String text) {
    final p = Profile.fromJson(Map<String, dynamic>.from(jsonDecode(text)));
    p.id = newId();
    addProfile(p);
  }

  // -------------------------------------------------------------- connection

  Future<void> connect() async {
    if (linkState != LinkState.disconnected) return;
    final p = active;
    final conn = p.connectionType == ConnectionType.ble ? BleConnection(p.ble) : WsConnection(p.wifi);
    linkState = LinkState.connecting;
    lastError = null;
    _addLog(LogKind.info, 'Connecting to ${conn.description}...');
    notifyListeners();
    try {
      await conn.connect();
      _conn = conn;
      _connSubs.add(conn.incoming.listen(_onIncoming));
      _connSubs.add(conn.onLost.listen((_) {
        _addLog(LogKind.error, 'Connection lost');
        _teardown();
      }));
      linkState = LinkState.connected;
      _addLog(LogKind.info, 'Connected');
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      _addLog(LogKind.error, 'Connect failed: $lastError');
      linkState = LinkState.disconnected;
      try {
        await conn.disconnect();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    final conn = _conn;
    if (conn == null) return;
    // Safety first: tell the device to stop before dropping the link.
    if (active.stopMessage.isNotEmpty) await send(active.stopMessage);
    await conn.disconnect();
    _addLog(LogKind.info, 'Disconnected');
    _teardown();
  }

  void _teardown() {
    for (final s in _connSubs) {
      s.cancel();
    }
    _connSubs.clear();
    _conn = null;
    linkState = LinkState.disconnected;
    toggleStates.clear();
    notifyListeners();
  }

  /// Sends [message] with the profile's line ending. Empty messages are ignored.
  Future<void> send(String message, {bool stream = false}) async {
    if (message.isEmpty) return;
    final conn = _conn;
    if (conn == null) return;
    _addLog(LogKind.tx, message, stream: stream);
    if (!stream) notifyListeners();
    try {
      await conn.send(message + active.lineEnding.value);
    } catch (e) {
      _addLog(LogKind.error, 'Send failed: $e');
      notifyListeners();
    }
  }

  void sendStop() => send(active.stopMessage);

  void _onIncoming(String chunk) {
    _rxBuffer += chunk;
    final lines = _rxBuffer.split('\n');
    _rxBuffer = lines.removeLast();
    for (final line in lines) {
      final l = line.trimRight();
      if (l.isNotEmpty) _addLog(LogKind.rx, l);
    }
    // Devices that never send newlines: flush whatever is pending.
    if (_rxBuffer.length > 256) {
      _addLog(LogKind.rx, _rxBuffer);
      _rxBuffer = '';
    }
    notifyListeners();
  }

  void _addLog(LogKind kind, String text, {bool stream = false}) {
    log.add(LogEntry(kind, text, stream: stream));
    if (log.length > _maxLog) log.removeRange(0, log.length - _maxLog);
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------- controls

  void pressControl(ControlItem c) {
    switch (c.type) {
      case ControlType.button:
        send(c.pressMsg);
      case ControlType.toggle:
        final on = !(toggleStates[c.id] ?? false);
        toggleStates[c.id] = on;
        send(on ? c.pressMsg : c.releaseMsg);
        notifyListeners();
      case ControlType.slider:
        break;
    }
  }

  void releaseControl(ControlItem c) {
    if (c.type == ControlType.button) send(c.releaseMsg);
  }

  double sliderValue(ControlItem c) => (sliderValues[c.id] ?? c.min).clamp(c.min, c.max);

  void setSlider(ControlItem c, double v, {bool sendNow = true}) {
    sliderValues[c.id] = v;
    if (sendNow) send(c.pressMsg.replaceAll('{v}', v.round().toString()));
    notifyListeners();
  }
}
