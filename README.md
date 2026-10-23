# pulse-responsive wearable prototype

A minimal iPhone app and XIAO ESP32-C6 firmware for a **non-medical** wearable prototype. The MAX30102 estimates heart rate; after a reliable reading stays above a configurable threshold for five seconds, the XIAO can play a soft, double-beat haptic pattern through a DRV2605L and one ERM motor. The phone shows live BPM over Bluetooth Low Energy (BLE) and optional recent-workout context from Apple Health.

**Current safety state:** sensing and BLE code are implemented, but motor output is **locked in firmware by default** because the exact DIANN motor voltage/current and safe DRV2605L settings remain unverified. The 200 mAh battery is **not** part of the USB breadboard build; its stated 100 mA maximum charge is below the XIAO schematic's 120 mA charger setting. This repository is not yet hardware-validated or wearable-ready.

## Project files

| Path | Purpose |
|---|---|
| `ios/Moodi.xcodeproj` | Native SwiftUI iPhone app project (iOS 16+) |
| `ios/Moodi/` | Live BPM UI, Core Bluetooth, HealthKit recorded-workout query |
| `firmware/MoodiWearable/` | Arduino sketch plus standalone threshold/haptic logic |
| `firmware/tests/` | Host-side safety/timing tests |
| `docs/BLE_PROTOCOL.md` | Exact BLE UUIDs and byte formats |

## Behavior

- The XIAO samples the optical sensor continuously at a configured 100 Hz and sends BLE heart-rate updates about once per second. The app saves **one valid point per minute** for its graph. Sampling only once a minute would miss changes and could not stop vibration promptly on lost contact.
- Initial adjustable thresholds are **start at 100 BPM** and **reset at 90 BPM**. Four plausible beat intervals and a regularity check are required. These are prototype signal checks, not clinical validation.
- A valid reading above the start threshold for **five seconds** requests a gentle 60-BPM-inspired double pulse. A valid reading below the reset threshold for five seconds stops it. Contact loss, sensor silence, or exercise override stops immediately. Every burst ends after **10 seconds**, followed by a **60-second cooldown**.
- The XIAO runs this logic without a phone. The iPhone can adjust thresholds, disable automatic response, and set an exercise override. A disconnected phone is not an emergency stop; disconnect USB for the desk prototype.
- The app optionally reads **recent recorded workouts** from Apple Health, where Fitness/Watch records may appear. This is **not** a dependable live indication that another app's workout is running. Use the manual exercise switch for a live override. Neither a recent workout nor its absence identifies anxiety.
- No cloud account, location tracking, analytics, or HealthKit writes are included.

## 1. Breadboard and firmware — USB only

Use the labels on the delivered boards, not only listing photos. The purchased MAX30102 breakout's VIN regulation and SDA/SCL pull-up voltage need confirmation before powering it. Provisional module-level wiring:

| XIAO ESP32-C6 | MAX30102 module | DRV2605L module |
|---|---|---|
| 3V3 | VIN **only after verifying 3.3 V compatibility** | VIN |
| GND | GND | GND |
| D4 / GPIO22 / SDA | SDA | SDA |
| D5 / GPIO23 / SCL | SCL | SCL |

Connect the motor only to the DRV2605L `motor −` and `motor +` pads, **not** XIAO GPIO. Leave sensor `INT` and driver `IN` unconnected. Do not attach the LiPo to XIAO BAT pads for this build.

1. Install Arduino IDE and the **esp32 by Espressif Systems** board package. Select **Seeed Studio XIAO ESP32C6** if available. Use a data-capable USB-C cable.
2. Install **SparkFun MAX3010x Sensor Library**, **Adafruit DRV2605 Library** (and its prompted BusIO dependency), and **NimBLE-Arduino 2.x** through Arduino Library Manager.
3. Open `firmware/MoodiWearable/MoodiWearable.ino` and upload it. Open Serial Monitor at **115200 baud**. Confirm sensor and driver detection; expected I²C addresses are `0x57` and `0x5A`.
4. Test no contact, motion, sensor removal, and USB disconnect. The app will show “motor output locked,” by design.
5. **Only after** verifying the exact motor's ratings, power budget, and DRV2605L register values in an off-body bench test, change `MOODI_MOTOR_APPROVED` to `1`. The sketch requires nonzero `MOODI_RATEDV_REG` and `MOODI_CLAMPV_REG` values. Do not copy the screenshot's clamp code `137` without evidence for this motor.

Seeed documents [D4/GPIO22 as SDA and D5/GPIO23 as SCL](https://wiki.seeedstudio.com/xiao_esp32c6_getting_started/). The [DRV2605L breakout reference](https://learn.adafruit.com/adafruit-drv2605-haptic-controller-breakout/pinouts) explains VIN, GND, I²C, and motor terminals; your purchased clone still needs visual checking. The [SparkFun library](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library) supports MAX30102. The [XIAO schematic](https://files.seeedstudio.com/wiki/SeeedStudio-XIAO-ESP32C6/XIAO-ESP32-C6_v1.0_SCH_PDF_24028.pdf) notes a 120 mA charging setting.

### Development dependencies on this Mac

Arduino CLI 1.5.1, Espressif `esp32:esp32` 3.3.12, SparkFun MAX3010x 1.1.2, Adafruit DRV2605 1.2.4, Adafruit BusIO 1.17.4, and NimBLE-Arduino 2.5.1 are installed. VS Code header paths are configured in `.vscode/c_cpp_properties.json`; reopen the folder or run **C/C++: Reset IntelliSense Database** if red include underlines persist. A real Arduino CLI compile is the authoritative check:

```sh
arduino-cli compile --fqbn esp32:esp32:XIAO_ESP32C6 firmware/MoodiWearable
```

## 2. iPhone app

This is a **native iOS app**, not a website: Core Bluetooth connects to XIAO and HealthKit provides permissioned access to workout records.

For first-time installation and a pass/fail device test, follow [the iPhone checklist](docs/IOS_DEVICE_CHECKLIST.md). No external Swift package is needed; full Xcode supplies the Apple frameworks.

1. Install the full Xcode app (this Mac currently has Command Line Tools but not full Xcode). Open `ios/Moodi.xcodeproj`.
2. Select the `Moodi` target. Under **Signing & Capabilities**, choose your Apple development team and confirm **HealthKit** is enabled. The entitlement and permission strings are already included. Change the bundle identifier if your team requires it.
3. Run on a **physical iPhone** with Bluetooth on. Grant Bluetooth permission, then tap **Connect to XIAO**. The XIAO advertises as `moodi`; encrypted controls may trigger an iOS pairing prompt.
4. Tap **Connect Health** to grant read access to Workouts, then **Refresh**. HealthKit may return no data even when read access was denied; the app therefore does not interpret “no workout” as “not exercising.”
5. Adjust steppers and tap **Send thresholds**. The exercise switch suppresses automatic response in XIAO even after phone disconnection, until turned off or XIAO reboot. The Stop button requires a current BLE connection.

The app uses foreground BLE. iOS may suspend it in the background; **XIAO-side sensing and stop rules continue**. It does not monitor another app's live workout session.

## Validation and unresolved hardware

- Confirm actual breakout VIN range, I²C pull-ups/levels, printed header order, and common ground on the delivered boards. Raw MAX30102 IC specifications are not the same as breakout-board VIN specifications.
- Obtain the exact DIANN motor rated voltage/current, startup current, and safe clamp. Measure the 3V3 rail under motor load before enabling output.
- The LiPo listing says “4.25 V / 100mAh” for maximum charging; the current unit should be **mA** and must be confirmed. The XIAO published charger setting is 120 mA. Until resolved: **USB only, no LiPo connection or on-body charging**.
- The prototype has no physical stop switch. A wearable revision needs local stop/power-off, insulated wiring, strain relief, sweat protection, and off-body charging.
- Elevated BPM has many causes. Neither the firmware nor Apple Health diagnoses anxiety. Uncertain contact or timing stops haptics rather than guessing.
- BLE uses encrypted bonding, but this no-display prototype cannot offer strong man-in-the-middle protection. Keep testing in a controlled setting.

### Checks available on this Mac

```sh
clang++ -std=c++17 -Wall -Wextra -Werror firmware/tests/heart_logic_test.cpp -o /tmp/moodi-heart-test && /tmp/moodi-heart-test
plutil -lint ios/Moodi.xcodeproj/project.pbxproj ios/Moodi/Info.plist ios/Moodi/Moodi.entitlements
swiftc -frontend -parse ios/Moodi/*.swift
```

These checks validate source syntax and hardware-independent logic. They do **not** replace Arduino/Xcode builds, BLE pairing, or bench tests with the delivered parts.
