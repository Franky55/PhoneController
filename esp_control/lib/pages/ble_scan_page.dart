import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_connection.dart';

class BleScanResult {
  BleScanResult(this.id, this.name);
  final String id;
  final String name;
}

/// Scans for BLE devices and returns the one the user taps.
class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key, required this.serviceUuid});

  final String serviceUuid;

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  List<ScanResult> _results = [];
  StreamSubscription? _sub;
  StreamSubscription? _scanningSub;
  bool _scanning = false;
  bool _onlyService = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = FlutterBluePlus.scanResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    _scan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scanningSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _error = null;
      _results = [];
    });
    try {
      if (!await ensureBlePermissions()) throw Exception('Bluetooth permission denied');
      await ensureBluetoothOn();
      await FlutterBluePlus.startScan(
        withServices: _onlyService ? [Guid(widget.serviceUuid)] : [],
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._results]..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select BLE device'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(onPressed: _scan, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Only devices with the configured service'),
            subtitle: Text(widget.serviceUuid, style: const TextStyle(fontSize: 11)),
            value: _onlyService,
            onChanged: (v) {
              setState(() => _onlyService = v);
              FlutterBluePlus.stopScan().then((_) => _scan());
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: sorted.isEmpty
                ? Center(child: Text(_scanning ? 'Scanning...' : 'No devices found. Tap refresh.'))
                : ListView(
                    children: [
                      for (final r in sorted)
                        ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(r.device.platformName.isNotEmpty
                              ? r.device.platformName
                              : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : '(no name)')),
                          subtitle: Text(r.device.remoteId.str),
                          trailing: Text('${r.rssi} dBm'),
                          onTap: () {
                            final name = r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : r.advertisementData.advName;
                            Navigator.pop(context, BleScanResult(r.device.remoteId.str, name));
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
