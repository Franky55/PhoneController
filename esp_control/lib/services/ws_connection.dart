import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/profile.dart';
import 'connection.dart';

class WsConnection implements DeviceConnection {
  WsConnection(this.settings);

  final WifiSettings settings;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _incoming = StreamController<String>.broadcast();
  final _lost = StreamController<void>.broadcast();
  bool _userDisconnect = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Stream<void> get onLost => _lost.stream;

  @override
  String get description => settings.uri.toString();

  @override
  Future<void> connect() async {
    _userDisconnect = false;
    final channel = WebSocketChannel.connect(settings.uri);
    try {
      await channel.ready.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      channel.sink.close();
      throw Exception('Timed out connecting to ${settings.uri}. '
          'Are you on the ESP32 WiFi? Try turning mobile data off.');
    }
    _channel = channel;
    _sub = channel.stream.listen(
      (data) => _incoming.add(data is String ? data : String.fromCharCodes(data as List<int>)),
      onDone: _onClosed,
      onError: (_) => _onClosed(),
    );
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_userDisconnect) _lost.add(null);
  }

  @override
  Future<void> send(String data) async {
    _channel?.sink.add(data);
  }

  @override
  Future<void> disconnect() async {
    _userDisconnect = true;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
