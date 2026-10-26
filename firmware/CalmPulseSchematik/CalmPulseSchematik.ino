#include <Arduino.h>
#include <Wire.h>
#include <MAX30105.h>
#include <heartRate.h>
#include <Adafruit_DRV2605.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <atomic>

// Thresholds are adjustable over BLE; defaults are temporary test values.
constexpr uint8_t RF_ENABLE_PIN = 3, RF_ANTENNA_PIN = 14;
// Temporary motor test thresholds; restore 100/90 after testing.
uint16_t startBpm = 50, stopBpm = 40;
constexpr uint32_t FINGER_IR = 50000, STALE_MS = 3000;
constexpr uint32_t MIN_CALM_MS = 60000; // minimum heartbeat-pattern session
constexpr uint8_t STRONG = 90, SOFT = 65; // signed RTP range 0..127
MAX30105 sensor;
Adafruit_DRV2605 haptic;
NimBLECharacteristic *measurement, *controlStatus;
constexpr char CONTROL_SERVICE[] = "8a7e1000-6f34-4c9a-9f30-2b739074f001";
constexpr char COMMAND_UUID[] = "8a7e1001-6f34-4c9a-9f30-2b739074f001";
constexpr char STATUS_UUID[] = "8a7e1002-6f34-4c9a-9f30-2b739074f001";
enum class Mode { Auto, Off };
Mode mode = Mode::Auto;
struct Command { char text[129]; };
QueueHandle_t commands;
std::atomic<bool> queueOverflow{false};
uint32_t commandSequence = 0;
const char *commandError = "";
class ControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo&) override {
    auto value = c->getValue();
    Command command{};
    if (value.size() == 0 || value.size() > 128) {
      // Empty text is rejected by the main-loop parser.
      command.text[0] = 0;
    } else {
      memcpy(command.text, value.c_str(), value.size());
    }
    // The BLE task only queues text. All motor/settings changes use loop().
    if (xQueueSend(commands, &command, 0) != pdTRUE) queueOverflow = true;
  }
} controlCallbacks;
bool sensorOK = false, driverOK = false, valid = false, calming = false;
bool contact = false;
uint32_t lastSample = 0, lastBeat = 0, sampleTick = 0, cycleStart = 0;
uint16_t bpm = 0, intervals[4] = {};
uint8_t count = 0, indexAt = 0, motorLevel = 255;

void motor(uint8_t value) {
  if (driverOK && value != motorLevel) {
    haptic.setRealtimeValue(value);
    motorLevel = value;
  }
}
void resetReading() {
  valid = false; bpm = 0; count = 0; indexAt = 0; lastBeat = 0;
}
void updateThreshold() {
  if (mode == Mode::Off) { calming = false; return; }
  // Auto mode: keep the pattern running through low BPM/lost contact for 60s.
  if (calming && uint32_t(millis() - cycleStart) < MIN_CALM_MS) return;
  if (!valid) calming = false;
  else if (!calming && bpm > startBpm) { calming = true; cycleStart = millis(); }
  else if (calming && bpm < stopBpm) calming = false;
}
void processCommands() {
  Command command;
  while (xQueueReceive(commands, &command, 0) == pdTRUE) {
    ++commandSequence;
    StaticJsonDocument<384> doc;
    auto error = deserializeJson(doc, command.text);
    if (error || !doc.is<JsonObject>() || doc.size() == 0) {
      commandError = "invalid_json"; continue;
    }
    bool badKey = false;
    for (JsonPair pair : doc.as<JsonObject>()) {
      const char *key = pair.key().c_str();
      if (strcmp(key, "start") && strcmp(key, "stop") && strcmp(key, "mode")) badKey = true;
    }
    if (badKey) { commandError = "unknown_key"; continue; }
    int nextStart = startBpm, nextStop = stopBpm;
    Mode nextMode = mode;
    if (doc.containsKey("start")) {
      if (!doc["start"].is<int>()) { commandError = "invalid_threshold"; continue; }
      nextStart = doc["start"].as<int>();
    }
    if (doc.containsKey("stop")) {
      if (!doc["stop"].is<int>()) { commandError = "invalid_threshold"; continue; }
      nextStop = doc["stop"].as<int>();
    }
    // Matches the sensor's supported inter-beat window, 40..220 BPM.
    if (nextStart < 40 || nextStart > 220 || nextStop < 40 || nextStop >= nextStart) {
      commandError = "invalid_threshold"; continue;
    }
    if (doc.containsKey("mode")) {
      if (!doc["mode"].is<const char*>()) { commandError = "invalid_mode"; continue; }
      const char *m = doc["mode"];
      if (!strcmp(m, "auto")) nextMode = Mode::Auto;
      else if (!strcmp(m, "on")) { commandError = "manual_on_disabled"; continue; }
      else if (!strcmp(m, "off")) nextMode = Mode::Off;
      else { commandError = "invalid_mode"; continue; }
    }
    // Atomic validation: no partial settings changes on a rejected command.
    startBpm = nextStart; stopBpm = nextStop; mode = nextMode;
    commandError = "";
    updateThreshold(); // never restarts the timer for an already-active session
    if (!calming) motor(0); // explicit Off bypasses the 60-second minimum
  }
  if (queueOverflow.exchange(false)) commandError = "queue_full";
}
void publishStatus() {
  StaticJsonDocument<384> doc;
  doc["seq"] = commandSequence;
  doc["start"] = startBpm; doc["stop"] = stopBpm;
  doc["mode"] = mode == Mode::Auto ? "auto" : "off";
  doc["active"] = calming;
  doc["contact"] = contact;
  doc["valid"] = valid;
  doc["driver"] = driverOK;
  uint32_t elapsed = millis() - cycleStart;
  doc["remaining"] = calming && elapsed < MIN_CALM_MS ? (MIN_CALM_MS - elapsed + 999) / 1000 : 0;
  doc["error"] = commandError;
  char text[200];
  size_t size = serializeJson(doc, text, sizeof(text));
  static String previous;
  if (previous != text) {
    previous = text;
    controlStatus->setValue(reinterpret_cast<const uint8_t*>(text), size);
    controlStatus->notify();
  }
}
void sample(uint32_t ir) {
  lastSample = millis();
  sampleTick += 10; // 100 samples/second, independent of FIFO drain timing
  bool detected = checkForBeat(ir); // keep filter running even without contact
  if (ir < FINGER_IR) { contact = false; resetReading(); return; }
  if (!contact) { contact = true; resetReading(); }
  if (!detected) return;
  uint32_t previous = lastBeat;
  lastBeat = sampleTick;
  if (!previous) return;
  uint32_t delta = sampleTick - previous;
  if (delta < 273 || delta > 1500) { resetReading(); lastBeat = sampleTick; return; }
  intervals[indexAt] = delta;
  indexAt = (indexAt + 1) % 4;
  if (count < 4) ++count;
  if (count < 4) return;
  uint32_t sum = 0;
  for (auto v : intervals) sum += v;
  bpm = (240000UL + sum / 2) / sum;
  valid = true;
  updateThreshold();
}
void setup() {
  Serial.begin(115200);
  // Seeed exact C6 RF switch: enable LOW, wait, onboard antenna LOW.
  pinMode(RF_ENABLE_PIN, OUTPUT); digitalWrite(RF_ENABLE_PIN, LOW); delay(100);
  pinMode(RF_ANTENNA_PIN, OUTPUT); digitalWrite(RF_ANTENNA_PIN, LOW);
  Wire.begin(22, 23); // XIAO D4=data, D5=clock
  Wire.setTimeOut(30);
  Serial.println("CalmPulse: expected I2C 0x57 and 0x5A");
  for (uint8_t a = 1; a < 127; ++a) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) Serial.printf("I2C: 0x%02X\n", a);
  }
  driverOK = haptic.begin(&Wire);
  if (driverOK) {
    haptic.useERM(); // library begin selects ERM open-loop; no auto-calibration
    // ERM open-loop OD_CLAMP = code * 5.6 / 255 V. 137 -> 3.01 V.
    haptic.writeRegister8(DRV2605_REG_CLAMPV, 137);
    haptic.setRealtimeValue(0);
    haptic.setMode(DRV2605_MODE_REALTIME);
    motor(0);
  }
  sensorOK = sensor.begin(Wire, I2C_SPEED_STANDARD);
  if (sensorOK) {
    // MAX30102 has RED + IR only. Average 1 at 100 Hz for heartbeat filter.
    sensor.setup(0x1F, 1, 2, 100, 411, 4096);
    sensor.setPulseAmplitudeRed(0x0A);
    sensor.setPulseAmplitudeIR(0x1F);
    sensor.clearFIFO();
  }
  commands = xQueueCreate(8, sizeof(Command));
  if (!commands) { motor(0); while (true) delay(1000); }
  NimBLEDevice::init("CalmPulse");
  NimBLEDevice::setMTU(185);
  auto server = NimBLEDevice::createServer();
  server->advertiseOnDisconnect(true);
  auto service = server->createService("180D");
  measurement = service->createCharacteristic("2A37", NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  uint8_t initial[] = {0x04, 0}; // contact supported, not detected
  measurement->setValue(initial, sizeof(initial));
  service->start();
  auto controls = server->createService(CONTROL_SERVICE);
  auto command = controls->createCharacteristic(COMMAND_UUID, NIMBLE_PROPERTY::WRITE, 128);
  command->setCallbacks(&controlCallbacks);
  controlStatus = controls->createCharacteristic(STATUS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY, 200);
  controls->start();
  publishStatus();
  auto advertising = NimBLEDevice::getAdvertising();
  advertising->setName("CalmPulse");
  advertising->addServiceUUID("180D");
  advertising->start();
  Serial.printf("Sensor=%s Driver=%s. Start>%u Stop<%u.\n", sensorOK?"OK":"MISSING", driverOK?"OK":"MISSING", startBpm, stopBpm);
}
void loop() {
  processCommands();
  uint32_t now = millis();
  if (sensorOK) {
    sensor.check();
    while (sensor.available()) {
      sample(sensor.getFIFOIR());
      sensor.nextSample();
    }
  }
  now = millis();
  // Invalidate stale readings; an active session still completes its minimum time.
  if (now - lastSample > 200 || (lastBeat && sampleTick - lastBeat > STALE_MS)) resetReading();
  updateThreshold(); // also stop expired sessions when contact/readings are lost
  if (calming && driverOK) {
    uint32_t phase = (now - cycleStart) % 1000; // calm 60 BPM, not measured BPM
    motor(phase < 110 ? STRONG : (phase >= 230 && phase < 310 ? SOFT : 0));
  } else motor(0);
  static uint32_t reportAt = 0;
  if (now - reportAt >= 1000) {
    reportAt = now;
    // Heart Rate Service: 8-bit BPM, contact supported/detected flags.
    uint8_t data[] = {uint8_t(valid ? 0x06 : 0x04), uint8_t(valid ? bpm : 0)};
    measurement->setValue(data, sizeof(data));
    measurement->notify();
    Serial.printf("BPM=%u valid=%u calm=%u motor=%u\n", bpm, valid, calming, motorLevel);
  }
  // Limit JSON serialization/notifications to 5 Hz; commands still apply in loop().
  static uint32_t statusAt = 0;
  if (now - statusAt >= 200) { statusAt = now; publishStatus(); }
  delay(1);
}
