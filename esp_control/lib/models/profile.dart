import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

enum ConnectionType { ble, wifi }

enum LineEnding {
  none(''),
  lf('\n'),
  crlf('\r\n');

  const LineEnding(this.value);
  final String value;
}

/// Which axes a joystick reports. Locked axes always send 0.
enum JoystickAxes { both, xOnly, yOnly }

enum ControlType { button, toggle, slider }

class BleSettings {
  String deviceId; // remoteId of the last selected device
  String deviceName;
  String serviceUuid;
  String rxUuid; // phone -> ESP32 (write)
  String txUuid; // ESP32 -> phone (notify)

  BleSettings({
    this.deviceId = '',
    this.deviceName = '',
    this.serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
    this.rxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
    this.txUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'serviceUuid': serviceUuid,
        'rxUuid': rxUuid,
        'txUuid': txUuid,
      };

  factory BleSettings.fromJson(Map<String, dynamic> j) {
    final d = BleSettings();
    return BleSettings(
      deviceId: j['deviceId'] ?? d.deviceId,
      deviceName: j['deviceName'] ?? d.deviceName,
      serviceUuid: j['serviceUuid'] ?? d.serviceUuid,
      rxUuid: j['rxUuid'] ?? d.rxUuid,
      txUuid: j['txUuid'] ?? d.txUuid,
    );
  }
}

class WifiSettings {
  String host;
  int port;
  String path;

  WifiSettings({this.host = '192.168.4.1', this.port = 81, this.path = '/'});

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: path);

  Map<String, dynamic> toJson() => {'host': host, 'port': port, 'path': path};

  factory WifiSettings.fromJson(Map<String, dynamic> j) => WifiSettings(
        host: j['host'] ?? '192.168.4.1',
        port: j['port'] ?? 81,
        path: j['path'] ?? '/',
      );
}

class JoystickConfig {
  String label;

  /// Message template. Placeholders: {x} and {y}.
  String template;
  JoystickAxes axes;

  JoystickConfig({required this.label, required this.template, this.axes = JoystickAxes.both});

  Map<String, dynamic> toJson() => {'label': label, 'template': template, 'axes': axes.name};

  factory JoystickConfig.fromJson(Map<String, dynamic> j) => JoystickConfig(
        label: j['label'] ?? '',
        template: j['template'] ?? '{"x":{x},"y":{y}}',
        axes: JoystickAxes.values.asNameMap()[j['axes']] ?? JoystickAxes.both,
      );
}

/// A configurable button, toggle or slider.
///
/// Message fields by type:
/// - button: [pressMsg] on press, [releaseMsg] on release (either may be empty)
/// - toggle: [pressMsg] when turned ON, [releaseMsg] when turned OFF
/// - slider: [pressMsg] is a template with {v} for the value
class ControlItem {
  String id;
  String label;
  ControlType type;
  String pressMsg;
  String releaseMsg;
  double min;
  double max;
  int divisions; // slider steps, 0 = continuous (sent as integer anyway)
  int color; // ARGB
  bool showOnController;

  ControlItem({
    String? id,
    required this.label,
    this.type = ControlType.button,
    this.pressMsg = '',
    this.releaseMsg = '',
    this.min = 0,
    this.max = 255,
    this.divisions = 0,
    this.color = 0xFF2196F3,
    this.showOnController = false,
  }) : id = id ?? newId();

  ControlItem copy() => ControlItem.fromJson(toJson())..id = newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'pressMsg': pressMsg,
        'releaseMsg': releaseMsg,
        'min': min,
        'max': max,
        'divisions': divisions,
        'color': color,
        'showOnController': showOnController,
      };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        id: j['id'],
        label: j['label'] ?? 'Button',
        type: ControlType.values.asNameMap()[j['type']] ?? ControlType.button,
        pressMsg: j['pressMsg'] ?? '',
        releaseMsg: j['releaseMsg'] ?? '',
        min: (j['min'] ?? 0).toDouble(),
        max: (j['max'] ?? 255).toDouble(),
        divisions: j['divisions'] ?? 0,
        color: j['color'] ?? 0xFF2196F3,
        showOnController: j['showOnController'] ?? false,
      );
}

/// A complete setup: connection + messages + controls.
class Profile {
  String id;
  String name;
  ConnectionType connectionType;
  BleSettings ble;
  WifiSettings wifi;
  LineEnding lineEnding;
  String stopMessage;
  JoystickConfig leftStick;
  JoystickConfig rightStick;
  int maxValue; // joystick values go from -maxValue to +maxValue
  int sendRateHz;
  bool repeatWhileHeld; // resend values at sendRateHz while a stick is off-center
  List<ControlItem> controls;

  Profile({
    String? id,
    required this.name,
    this.connectionType = ConnectionType.ble,
    BleSettings? ble,
    WifiSettings? wifi,
    this.lineEnding = LineEnding.lf,
    this.stopMessage = '{"cmd":"stop"}',
    JoystickConfig? leftStick,
    JoystickConfig? rightStick,
    this.maxValue = 100,
    this.sendRateHz = 20,
    this.repeatWhileHeld = true,
    List<ControlItem>? controls,
  })  : id = id ?? newId(),
        ble = ble ?? BleSettings(),
        wifi = wifi ?? WifiSettings(),
        leftStick = leftStick ??
            JoystickConfig(label: 'Throttle', template: '{"j":"L","x":{x},"y":{y}}', axes: JoystickAxes.yOnly),
        rightStick = rightStick ??
            JoystickConfig(label: 'Steering', template: '{"j":"R","x":{x},"y":{y}}', axes: JoystickAxes.xOnly),
        controls = controls ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connectionType': connectionType.name,
        'ble': ble.toJson(),
        'wifi': wifi.toJson(),
        'lineEnding': lineEnding.name,
        'stopMessage': stopMessage,
        'leftStick': leftStick.toJson(),
        'rightStick': rightStick.toJson(),
        'maxValue': maxValue,
        'sendRateHz': sendRateHz,
        'repeatWhileHeld': repeatWhileHeld,
        'controls': controls.map((c) => c.toJson()).toList(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'],
        name: j['name'] ?? 'Profile',
        connectionType: ConnectionType.values.asNameMap()[j['connectionType']] ?? ConnectionType.ble,
        ble: j['ble'] is Map ? BleSettings.fromJson(Map<String, dynamic>.from(j['ble'])) : null,
        wifi: j['wifi'] is Map ? WifiSettings.fromJson(Map<String, dynamic>.from(j['wifi'])) : null,
        lineEnding: LineEnding.values.asNameMap()[j['lineEnding']] ?? LineEnding.lf,
        stopMessage: j['stopMessage'] ?? '{"cmd":"stop"}',
        leftStick: j['leftStick'] is Map ? JoystickConfig.fromJson(Map<String, dynamic>.from(j['leftStick'])) : null,
        rightStick: j['rightStick'] is Map ? JoystickConfig.fromJson(Map<String, dynamic>.from(j['rightStick'])) : null,
        maxValue: j['maxValue'] ?? 100,
        sendRateHz: j['sendRateHz'] ?? 20,
        repeatWhileHeld: j['repeatWhileHeld'] ?? true,
        controls: (j['controls'] as List? ?? [])
            .map((c) => ControlItem.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
      );

  /// Default profile for a 2-motor RC car, matching the example firmware.
  factory Profile.rcCar() => Profile(
        name: 'RC Car',
        controls: [
          ControlItem(
              label: 'Horn',
              pressMsg: '{"cmd":"horn","on":1}',
              releaseMsg: '{"cmd":"horn","on":0}',
              color: 0xFFFF9800,
              showOnController: true),
          ControlItem(
              label: 'Lights',
              type: ControlType.toggle,
              pressMsg: '{"cmd":"lights","on":1}',
              releaseMsg: '{"cmd":"lights","on":0}',
              color: 0xFFFFEB3B,
              showOnController: true),
          ControlItem(
              label: 'Max speed',
              type: ControlType.slider,
              pressMsg: '{"cmd":"maxspeed","v":{v}}',
              min: 0,
              max: 255,
              color: 0xFF4CAF50),
          ControlItem(label: 'Ping', pressMsg: '{"cmd":"ping"}', color: 0xFF9C27B0),
        ],
      );
}
