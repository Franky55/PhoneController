# PhoneController

An Android app (Flutter) to control an ESP32 over **Bluetooth LE** or **WiFi**, like an RC car,
a robot, or any other project. Buttons, joysticks and the messages they send are all configurable in the app.

## Repository layout

| Folder | Content |
|---|---|
| [`esp_control/`](esp_control) | Flutter app (Android) |
| [`esp32_firmware/`](esp32_firmware) | Example ESP32 firmware (PlatformIO, Arduino framework) |

## Features

- **Controller page**: two joysticks, a STOP button and quick-access buttons (landscape).
- **Buttons page**: momentary buttons, toggles and sliders.
- **Console page**: live log of sent and received messages, and raw message input.
- **Settings page**:
  - Bluetooth LE or WiFi (WebSocket) connection
  - Editable messages for every button, joystick and slider
  - Multiple profiles, which you can export/import as JSON
- **Safety**: the STOP message is sent before disconnecting, and the firmware has a 500 ms failsafe.

## Getting started

### App

Requirements: Flutter 3.47+ and an Android phone with USB debugging enabled.

```bash
cd esp_control
flutter pub get
flutter run          # run on a connected phone
flutter build apk    # build a release APK
```

### Firmware

Requirements: [PlatformIO](https://platformio.org/) and an ESP32 dev kit.

```bash
cd esp32_firmware
pio run -t upload    # build and flash
pio device monitor   # serial monitor (115200 baud)
```

## Connecting

**Bluetooth LE**: in *Settings → Connection*, choose Bluetooth LE, scan, select **ESP-Control**,
then tap **Connect**.

**WiFi**: join the WiFi network **ESP-Control** (password `espcontrol`), choose WiFi in Settings,
then tap **Connect**. The default address is `ws://192.168.4.1:81/`.

> If WiFi won't connect, turn off mobile data. Android may be routing traffic over 4G/5G
> because the ESP32 hotspot has no internet.

## Message protocol

Each message is sent as one line (`\n`-terminated by default). The defaults below match the example firmware,
and every message can be changed in the app.

| Action | Default message |
|---|---|
| Left joystick | `{"j":"L","x":0,"y":80}` |
| Right joystick | `{"j":"R","x":-40,"y":0}` |
| STOP | `{"cmd":"stop"}` |
| Horn (press / release) | `{"cmd":"horn","on":1}` / `{"cmd":"horn","on":0}` |
| Lights (toggle) | `{"cmd":"lights","on":1}` / `{"cmd":"lights","on":0}` |
| Max speed (slider) | `{"cmd":"maxspeed","v":200}` |
| Ping | `{"cmd":"ping"}` → reply `{"t":"pong"}` |

Joystick values range from −100 to 100 (right and up are positive). They're sent at 20 Hz while they change,
and repeated while a stick is held, so the firmware can stop the motors if messages stop arriving.

BLE uses the Nordic UART Service: service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`,
RX `6E400002-…` (app writes), TX `6E400003-…` (ESP32 notifies).

## Example wiring (L298N)

| Function | ESP32 pin |
|---|---|
| Left motor ENA / IN1 / IN2 | 25 / 26 / 27 |
| Right motor ENB / IN3 / IN4 | 14 / 33 / 32 |
| Horn / buzzer | 13 |
| Lights | 2 (on-board LED) |

To add a command, add a branch to `handleLine()` in [`esp32_firmware/src/main.cpp`](esp32_firmware/src/main.cpp).

## Notes

- BLE uses [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus) with `License.nonprofit`,
  which covers personal and educational use.
- `kotlin.incremental=false` in `esp_control/android/gradle.properties` works around a Windows build bug.
  The bug happens when the project and the pub cache are on different drives.
