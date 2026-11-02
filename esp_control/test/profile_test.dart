import 'dart:convert';

import 'package:esp_control/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile survives a JSON round trip', () {
    final p = Profile.rcCar()
      ..connectionType = ConnectionType.wifi
      ..wifi.port = 1234
      ..lineEnding = LineEnding.crlf;
    final back = Profile.fromJson(jsonDecode(jsonEncode(p.toJson())));

    expect(back.toJson(), p.toJson());
    expect(back.controls.length, 4);
    expect(back.controls[1].type, ControlType.toggle);
    expect(back.leftStick.axes, JoystickAxes.yOnly);
  });

  test('missing fields fall back to defaults', () {
    final p = Profile.fromJson({'name': 'Bare'});
    expect(p.ble.serviceUuid, '6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
    expect(p.wifi.uri.toString(), 'ws://192.168.4.1:81/');
    expect(p.sendRateHz, 20);
  });
}
