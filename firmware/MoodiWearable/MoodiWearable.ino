#include <Arduino.h>
#include <Wire.h>
#include <MAX30105.h>
#include <heartRate.h>
#include <Adafruit_DRV2605.h>
#include <NimBLEDevice.h>
#include <atomic>

#include "HeartLogic.h"

// Set to 1 only after the exact motor's rated voltage/current, the breakout's
// supply, and DRV2605L register values have been checked on the bench.
#define MOODI_MOTOR_APPROVED 0
#define MOODI_RATEDV_REG 0
#define MOODI_CLAMPV_REG 0
#if MOODI_MOTOR_APPROVED && (!MOODI_RATEDV_REG || !MOODI_CLAMPV_REG)
#error "Verify the motor and set DRV2605L RATEDV/CLAMPV before enabling output"
#endif

constexpr uint8_t kSdaPin = 22;  // XIAO D4
constexpr uint8_t kSclPin = 23;  // XIAO D5
constexpr uint32_t kContactIR = 50000;  // Tunable prototype contact heuristic
constexpr uint32_t kBeatStaleMs = 3000;
constexpr uint8_t kStrongRtp = 80;  // Only used after motor approval
constexpr uint8_t kSoftRtp = 55;
constexpr char kServiceUUID[] = "8f941100-b6b1-4f96-9f4d-356db1fe7a10";
constexpr char kStatusUUID[]  = "8f941101-b6b1-4f96-9f4d-356db1fe7a10";
constexpr char kControlUUID[] = "8f941102-b6b1-4f96-9f4d-356db1fe7a10";

MAX30105 sensor;
Adafruit_DRV2605 driver;
HeartLogic logic;
NimBLECharacteristic* measurement = nullptr;
NimBLECharacteristic* statusCharacteristic = nullptr;
std::atomic<uint32_t> pendingCommand{0};

bool sensorOK = false;
bool driverOK = false;
bool contact = false;
bool readingValid = false;
uint8_t bpm = 0;
uint8_t appliedMotorLevel = 255;
uint32_t lastSampleMs = 0;
uint32_t lastBeatMs = 0;
uint32_t sampleClockMs = 0;
uint32_t lastReportMs = 0;
uint32_t intervals[4] = {};
uint8_t intervalCount = 0;
uint8_t intervalIndex = 0;

void resetReading() {
  contact = false;
  readingValid = false;
  bpm = 0;
  intervalCount = 0;
  intervalIndex = 0;
  lastBeatMs = 0;
}

void applyMotor(uint8_t value) {
  if (!driverOK) return;
#if !MOODI_MOTOR_APPROVED
  value = 0;
#endif
  if (value != appliedMotorLevel) {
    driver.setRealtimeValue(value);
    appliedMotorLevel = value;
  }
}

void sampleIR(uint32_t ir) {
  const uint32_t now = millis();
  lastSampleMs = now;
  sampleClockMs += 10;  // MAX30102 configured for 100 samples/second
  const bool beat = checkForBeat(ir);  // keep filter running on every sample
  if (ir < kContactIR) {
    resetReading();
    return;
  }
  if (!contact) {
    contact = true;
    readingValid = false;
    lastBeatMs = 0;
    intervalCount = 0;
    return;
  }
  if (!beat) return;
  const uint32_t previous = lastBeatMs;
  lastBeatMs = sampleClockMs;
  if (!previous) return;
  const uint32_t interval = sampleClockMs - previous;
  if (interval < 300 || interval > 1500) {
    readingValid = false;
    intervalCount = 0;
    return;
  }
  intervals[intervalIndex] = interval;
  intervalIndex = (intervalIndex + 1) % 4;
  if (intervalCount < 4) ++intervalCount;
  if (intervalCount < 4) return;

  uint32_t sum = 0;
  uint32_t shortest = UINT32_MAX;
  uint32_t longest = 0;
  for (uint32_t item : intervals) {
    sum += item;
    if (item < shortest) shortest = item;
    if (item > longest) longest = item;
  }
  const uint32_t mean = sum / 4;
  // Reject obviously irregular windows; motion artefacts still require testing.
  if ((longest - shortest) * 100 > mean * 30) {
    readingValid = false;
    return;
  }
  const uint32_t candidate = (240000UL + sum / 2) / sum;
  if (candidate >= 40 && candidate <= 200) {
    bpm = static_cast<uint8_t>(candidate);
    readingValid = true;
  }
}

class ControlCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo&) override {
    const std::string bytes = characteristic->getValue();
    if (bytes.empty() || bytes.size() > 4) return;
    uint32_t packed = static_cast<uint8_t>(bytes.size()) << 24;
    for (size_t i = 0; i < bytes.size(); ++i)
      packed |= static_cast<uint32_t>(static_cast<uint8_t>(bytes[i])) << (i * 8);
    pendingCommand.store(packed);
  }
};

ControlCallbacks controlCallbacks;

void handleCommand(uint32_t now) {
  const uint32_t packed = pendingCommand.exchange(0);
  if (!packed) return;
  const uint8_t count = packed >> 24;
  const uint8_t command = packed & 0xff;
  const uint8_t a = (packed >> 8) & 0xff;
  const uint8_t b = (packed >> 16) & 0xff;
  switch (command) {
    case 1: if (count == 2 && a <= 1) { logic.automatic = a; logic.stopNow(now); } break;
    case 2: if (count == 2 && a <= 1) { logic.exerciseOverride = a; logic.stopNow(now); } break;
    case 3: if (count == 3) logic.setThresholds(a, b); break;
    case 4: if (count == 1) { logic.automatic = false; logic.stopNow(now); } break;
  }
}

void reportBLE() {
  const uint8_t heartRate[2] = {static_cast<uint8_t>(readingValid ? 0x06 : 0x04),
                                static_cast<uint8_t>(readingValid ? bpm : 0)};
  measurement->setValue(heartRate, sizeof(heartRate));
  measurement->notify();

  uint8_t flags = 0;
  if (readingValid) flags |= 1;
  if (logic.active && MOODI_MOTOR_APPROVED && driverOK) flags |= 2;
  if (logic.automatic) flags |= 4;
  if (logic.exerciseOverride) flags |= 8;
  if (sensorOK) flags |= 16;
  if (driverOK) flags |= 32;
  if (MOODI_MOTOR_APPROVED && driverOK) flags |= 64;
  const uint8_t status[5] = {1, flags, heartRate[1], logic.startBpm, logic.stopBpm};
  statusCharacteristic->setValue(status, sizeof(status));
  statusCharacteristic->notify();
  Serial.printf("BPM=%u valid=%u response=%u motorReady=%u\n",
                bpm, readingValid, logic.active, bool(flags & 64));
}

void setup() {
  Serial.begin(115200);
  // Seeed: GPIO3 LOW enables RF switch, GPIO14 LOW selects built-in antenna.
  pinMode(3, OUTPUT); digitalWrite(3, LOW);
  delay(100);
  pinMode(14, OUTPUT); digitalWrite(14, LOW);
  Wire.begin(kSdaPin, kSclPin);
  Wire.setTimeOut(30);

  sensorOK = sensor.begin(Wire, I2C_SPEED_STANDARD);
  if (sensorOK) {
    sensor.setup(0x1F, 1, 2, 100, 411, 4096);  // RED + IR, 100 Hz
    sensor.setPulseAmplitudeRed(0x0A);
    sensor.setPulseAmplitudeIR(0x1F);
    sensor.clearFIFO();
  }
  driverOK = driver.begin(&Wire);
  if (driverOK) {
    driver.useERM();
    driver.setRealtimeValue(0);
#if MOODI_MOTOR_APPROVED
    driver.writeRegister8(DRV2605_REG_RATEDV, MOODI_RATEDV_REG);
    driver.writeRegister8(DRV2605_REG_CLAMPV, MOODI_CLAMPV_REG);
#endif
    driver.setMode(DRV2605_MODE_REALTIME);
    applyMotor(0);
  }

  NimBLEDevice::init("moodi");
  NimBLEDevice::setSecurityAuth(true, false, true);  // encrypted bonding; no MITM with this hardware
  auto* server = NimBLEDevice::createServer();
  server->advertiseOnDisconnect(true);
  auto* heartService = server->createService("180D");
  measurement = heartService->createCharacteristic("2A37", NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::NOTIFY);
  const uint8_t initialHeart[2] = {0x04, 0};
  measurement->setValue(initialHeart, sizeof(initialHeart));
  heartService->start();

  auto* moodiService = server->createService(kServiceUUID);
  statusCharacteristic = moodiService->createCharacteristic(kStatusUUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::NOTIFY);
  auto* control = moodiService->createCharacteristic(kControlUUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC);
  control->setCallbacks(&controlCallbacks);
  moodiService->start();
  auto* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUUID);
  // Keep the 128-bit UUID and short name inside the legacy advertising budget.
  // The standard Heart Rate service is still discoverable after connecting.
  advertising->setName("moodi");
  advertising->start();
  Serial.printf("Sensor %s; driver %s; motor output LOCKED=%u\n",
                sensorOK ? "OK" : "MISSING", driverOK ? "OK" : "MISSING", !MOODI_MOTOR_APPROVED);
}

void loop() {
  const uint32_t now = millis();
  handleCommand(now);
  if (sensorOK) {
    sensor.check();
    while (sensor.available()) {
      sampleIR(sensor.getFIFOIR());
      sensor.nextSample();
    }
  }
  if (!sensorOK || now - lastSampleMs > 200 ||
      (lastBeatMs && sampleClockMs - lastBeatMs > kBeatStaleMs)) {
    resetReading();
  }
  logic.update(now, bpm, readingValid);
  const uint8_t requested = logic.level(now, kStrongRtp, kSoftRtp);
  applyMotor(requested);
  if (now - lastReportMs >= 1000UL) {
    lastReportMs = now;
    reportBLE();
  }
  delay(1);
}
