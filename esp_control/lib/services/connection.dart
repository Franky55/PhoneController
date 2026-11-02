import 'dart:async';

enum LinkState { disconnected, connecting, connected }

/// Common interface for every transport (BLE, WebSocket, ...).
abstract class DeviceConnection {
  /// Raw text chunks received from the device (not necessarily full lines).
  Stream<String> get incoming;

  /// Fires when the link drops on its own (device off, out of range...).
  Stream<void> get onLost;

  Future<void> connect();
  Future<void> send(String data);
  Future<void> disconnect();

  /// Human readable target, for the UI ("ESP-Control (AA:BB:..)", "ws://...").
  String get description;
}
