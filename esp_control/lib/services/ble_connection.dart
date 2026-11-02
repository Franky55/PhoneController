import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/profile.dart';
import 'connection.dart';

/// Asks for the runtime permissions BLE needs. Returns true if granted.
Future<bool> ensureBlePermissions() async {
  if (!Platform.isAndroid) return true;
  final results = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse, // only required on Android 11 and lower
  ].request();
  final scan = results[Permission.bluetoothScan]!;
  final connect = results[Permission.bluetoothConnect]!;
  final location = results[Permission.locationWhenInUse]!;
  // On Android 12+ scan/connect matter; on older versions they report granted
  // and location is what matters.
  return (scan.isGranted && connect.isGranted) || location.isGranted;
}

/// Makes sure the Bluetooth adapter is on (asks the user on Android).
Future<void> ensureBluetoothOn() async {
  if (await FlutterBluePlus.isSupported == false) {
    throw Exception('Bluetooth LE is not supported on this device');
  }
  if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
    await FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on)
        .timeout(const Duration(seconds: 10));
  }
}

class BleConnection implements DeviceConnection {
  BleConnection(this.settings);

  final BleSettings settings;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  final _incoming = StreamController<String>.broadcast();
  final _lost = StreamController<void>.broadcast();
  final List<StreamSubscription> _subs = [];
  bool _userDisconnect = false;
  Future<void> _writeChain = Future.value();

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Stream<void> get onLost => _lost.stream;

  @override
  String get description =>
      settings.deviceName.isNotEmpty ? '${settings.deviceName} (${settings.deviceId})' : settings.deviceId;

  @override
  Future<void> connect() async {
    if (settings.deviceId.isEmpty) {
      throw Exception('No BLE device selected. Pick one in Settings.');
    }
    if (!await ensureBlePermissions()) {
      throw Exception('Bluetooth permission denied');
    }
    await ensureBluetoothOn();

    _userDisconnect = false;
    final device = BluetoothDevice.fromId(settings.deviceId);
    _device = device;
    // FlutterBluePlus license: free for personal / educational / nonprofit use.
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));

    final services = await device.discoverServices();
    final service = services.where((s) => s.uuid == Guid(settings.serviceUuid)).firstOrNull;
    if (service == null) {
      await device.disconnect();
      throw Exception('Service ${settings.serviceUuid} not found on device');
    }
    _rx = service.characteristics.where((c) => c.uuid == Guid(settings.rxUuid)).firstOrNull;
    _tx = service.characteristics.where((c) => c.uuid == Guid(settings.txUuid)).firstOrNull;
    if (_rx == null) {
      await device.disconnect();
      throw Exception('RX characteristic ${settings.rxUuid} not found');
    }

    final tx = _tx;
    if (tx != null && (tx.properties.notify || tx.properties.indicate)) {
      _subs.add(tx.onValueReceived.listen((bytes) {
        _incoming.add(utf8.decode(bytes, allowMalformed: true));
      }));
      await tx.setNotifyValue(true);
    }

    _subs.add(device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !_userDisconnect) {
        _cleanup();
        _lost.add(null);
      }
    }));
  }

  @override
  Future<void> send(String data) {
    // Serialize writes: BLE only allows one outstanding GATT operation.
    _writeChain = _writeChain.then((_) => _write(data)).catchError((_) {});
    return _writeChain;
  }

  Future<void> _write(String data) async {
    final rx = _rx;
    final device = _device;
    if (rx == null || device == null) return;
    final bytes = utf8.encode(data);
    final noResponse = rx.properties.writeWithoutResponse;
    final chunk = (device.mtuNow - 3).clamp(20, 512);
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
      await rx.write(bytes.sublist(i, end), withoutResponse: noResponse);
    }
  }

  @override
  Future<void> disconnect() async {
    _userDisconnect = true;
    final device = _device;
    _cleanup();
    await device?.disconnect();
  }

  void _cleanup() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _rx = null;
    _tx = null;
  }
}
