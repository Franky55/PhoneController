// ESP Control - example firmware for a 2-motor RC car (L298N style driver).
//
// Transports (both active at once):
//   - BLE: Nordic UART service, device name "ESP-Control"
//   - WiFi: hotspot "ESP-Control" / "espcontrol", WebSocket on ws://192.168.4.1:81/
//
// Messages are one JSON object per line (the app adds "\n"):
//   {"j":"L","x":0,"y":80}        left stick  (y = throttle, -100..100)
//   {"j":"R","x":-40,"y":0}       right stick (x = steering, -100..100)
//   {"cmd":"stop"}
//   {"cmd":"horn","on":1}         / 0
//   {"cmd":"lights","on":1}       / 0
//   {"cmd":"maxspeed","v":200}    0..255
//   {"cmd":"ping"}                -> replies {"t":"pong"}
// Anything else is printed on Serial and echoed back as {"t":"unknown",...}.

#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <WebSocketsServer.h>
#include <WiFi.h>

// ------------------------------------------------------------------ config
static const char *DEVICE_NAME = "ESP-Control";
static const char *AP_SSID = "ESP-Control";
static const char *AP_PASS = "espcontrol"; // at least 8 characters
static const uint16_t WS_PORT = 81;

#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // app -> ESP32
#define TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // ESP32 -> app

// Motor driver pins (L298N: ENA/IN1/IN2 = left, ENB/IN3/IN4 = right).
static const int PIN_ENA = 25, PIN_IN1 = 26, PIN_IN2 = 27;
static const int PIN_ENB = 14, PIN_IN3 = 33, PIN_IN4 = 32;
static const int PIN_HORN = 13;
static const int PIN_LIGHTS = 2; // on-board LED on most dev kits

// Stop the motors if no joystick message arrives for this long while moving.
static const uint32_t FAILSAFE_MS = 500;

// ------------------------------------------------------------------- state
static int throttle = 0; // -100..100
static int steering = 0; // -100..100
static int maxSpeed = 255;
static uint32_t lastDriveMs = 0;

static QueueHandle_t lineQueue; // complete lines from any transport
struct Line {
  char text[200];
};

static BLECharacteristic *txChar = nullptr;
static volatile bool bleConnected = false;
static WebSocketsServer ws(WS_PORT);

// ----------------------------------------------------------------- outputs
static void setMotor(int en, int inA, int inB, int value) {
  value = constrain(value, -100, 100);
  digitalWrite(inA, value > 0);
  digitalWrite(inB, value < 0);
  analogWrite(en, abs(value) * maxSpeed / 100);
}

static void applyDrive() {
  // Arcade mix: throttle + steering -> left/right wheel speeds.
  setMotor(PIN_ENA, PIN_IN1, PIN_IN2, throttle + steering);
  setMotor(PIN_ENB, PIN_IN3, PIN_IN4, throttle - steering);
}

static void stopAll() {
  throttle = steering = 0;
  applyDrive();
  digitalWrite(PIN_HORN, LOW);
}

// Sends one line to every connected app.
static void sendLine(const String &s) {
  String line = s + "\n";
  if (bleConnected && txChar) {
    txChar->setValue((uint8_t *)line.c_str(), line.length());
    txChar->notify();
  }
  ws.broadcastTXT(line);
}

// ---------------------------------------------------------------- protocol
static void handleLine(const char *line) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) {
    Serial.printf("Not JSON: %s\n", line);
    return;
  }

  const char *stick = doc["j"] | "";
  if (*stick) {
    if (stick[0] == 'L') throttle = doc["y"] | 0;
    if (stick[0] == 'R') steering = doc["x"] | 0;
    lastDriveMs = millis();
    applyDrive();
    return;
  }

  String cmd = doc["cmd"] | "";
  if (cmd == "stop") {
    stopAll();
    sendLine("{\"t\":\"stopped\"}");
  } else if (cmd == "horn") {
    digitalWrite(PIN_HORN, (doc["on"] | 0) ? HIGH : LOW);
  } else if (cmd == "lights") {
    digitalWrite(PIN_LIGHTS, (doc["on"] | 0) ? HIGH : LOW);
  } else if (cmd == "maxspeed") {
    maxSpeed = constrain((int)(doc["v"] | 255), 0, 255);
    applyDrive();
    sendLine("{\"t\":\"maxspeed\",\"v\":" + String(maxSpeed) + "}");
  } else if (cmd == "ping") {
    sendLine("{\"t\":\"pong\"}");
  } else {
    Serial.printf("Unknown: %s\n", line);
    JsonDocument reply;
    reply["t"] = "unknown";
    reply["msg"] = line;
    String out;
    serializeJson(reply, out);
    sendLine(out);
  }
}

// Splits a byte stream into lines and queues them for loop().
static void feed(String &buffer, const uint8_t *data, size_t len) {
  for (size_t i = 0; i < len; i++) {
    char c = (char)data[i];
    if (c == '\n' || c == '\r') {
      if (buffer.length() > 0) {
        Line l;
        strlcpy(l.text, buffer.c_str(), sizeof(l.text));
        xQueueSend(lineQueue, &l, 0);
        buffer = "";
      }
    } else if (buffer.length() < sizeof(Line::text) - 1) {
      buffer += c;
    }
  }
}

// --------------------------------------------------------------------- BLE
static String bleBuffer;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    bleConnected = true;
    Serial.println("BLE connected");
  }
  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    Serial.println("BLE disconnected");
    Line l;
    strlcpy(l.text, "{\"cmd\":\"stop\"}", sizeof(l.text));
    xQueueSend(lineQueue, &l, 0);
    server->getAdvertising()->start(); // allow reconnecting
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    // getValue() is std::string on core 2.x and String on core 3.x; c_str() works for both.
    String v = String(c->getValue().c_str());
    feed(bleBuffer, (const uint8_t *)v.c_str(), v.length());
  }
};

static void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(SERVICE_UUID);

  txChar = service->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  BLECharacteristic *rx = service->createCharacteristic(
      RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCallbacks());

  service->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising as " + String(DEVICE_NAME));
}

// --------------------------------------------------------------- WebSocket
static String wsBuffer;

static void onWsEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t len) {
  switch (type) {
  case WStype_CONNECTED: {
    Serial.printf("WS client %u connected\n", num);
    String hello = "{\"t\":\"hello\",\"name\":\"" + String(DEVICE_NAME) + "\"}\n";
    ws.sendTXT(num, hello);
    break;
  }
  case WStype_DISCONNECTED:
    Serial.printf("WS client %u disconnected\n", num);
    stopAll();
    break;
  case WStype_TEXT:
    feed(wsBuffer, payload, len);
    // Also accept messages sent without a line ending (one message per frame).
    if (wsBuffer.length() > 0) {
      const uint8_t nl = '\n';
      feed(wsBuffer, &nl, 1);
    }
    break;
  default:
    break;
  }
}

static void setupWifi() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.printf("WiFi AP \"%s\" at %s, WebSocket port %u\n", AP_SSID, WiFi.softAPIP().toString().c_str(), WS_PORT);
  ws.begin();
  ws.onEvent(onWsEvent);
}

// ------------------------------------------------------------- setup/loop
void setup() {
  Serial.begin(115200);
  for (int p : {PIN_ENA, PIN_IN1, PIN_IN2, PIN_ENB, PIN_IN3, PIN_IN4, PIN_HORN, PIN_LIGHTS}) {
    pinMode(p, OUTPUT);
    digitalWrite(p, LOW);
  }
  lineQueue = xQueueCreate(32, sizeof(Line));
  setupWifi();
  setupBle();
}

void loop() {
  ws.loop();

  Line l;
  while (xQueueReceive(lineQueue, &l, 0) == pdTRUE) {
    Serial.printf("<< %s\n", l.text);
    handleLine(l.text);
  }

  // Failsafe: the app resends stick values while held, so silence means trouble.
  if ((throttle || steering) && millis() - lastDriveMs > FAILSAFE_MS) {
    Serial.println("Failsafe: no drive messages, stopping");
    stopAll();
  }

  static uint32_t lastStatus = 0;
  if (millis() - lastStatus > 2000) {
    lastStatus = millis();
    sendLine("{\"t\":\"status\",\"up\":" + String(millis() / 1000) + ",\"thr\":" + String(throttle) +
             ",\"str\":" + String(steering) + "}");
  }
}
