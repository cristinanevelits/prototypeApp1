# pulse-responsive wearable prototype

A minimal iPhone app for a **non-medical** XIAO ESP32-C6 wearable prototype. The MAX30102 estimates heart rate, and the XIAO drives a calm haptic pattern through a DRV2605L and one ERM motor. The phone shows live BPM over Bluetooth Low Energy (BLE), sends response settings, and optionally shows recent-workout context from Apple Health.

**Current prototype state (October 26):** the user uploaded a new `CalmPulse` program through Schematik. Its full source was supplied in a conversation attachment and defines the BLE JSON protocol documented in [`docs/BLE_PROTOCOL.md`](docs/BLE_PROTOCOL.md). The separate `firmware/MoodiWearable/` sketch in this repo is **not** that uploaded program; do not upload it over the working XIAO. Motor settings have not been independently verified against the exact motor datasheet; test off-body. The 200 mAh battery is **not** part of the USB breadboard build; its stated 100 mA maximum charge is below the XIAO schematic's 120 mA charger setting. This is not yet wearable-ready.

## Project files

| Path | Purpose |
|---|---|
| `ios/Moodi.xcodeproj` | Native SwiftUI iPhone app project (iOS 16+) |
| `ios/Moodi/` | Live BPM UI, Core Bluetooth, HealthKit recorded-workout query, shared widget settings |
| `ios/MoodiWidget/` | iOS 17+ home-screen widget for vibration and threshold controls |
| `firmware/MoodiWearable/` | Older, separate Arduino sketch; not the program now on the XIAO |
| `firmware/CalmPulseSchematik/` | Unflashed copy of the pasted Schematik program with manual On removed and status throttled |
| `firmware/tests/` | Tests for that older sketch, not the Schematik upload |
| `docs/BLE_PROTOCOL.md` | BLE UUIDs and JSON formats of the current Schematik program |

## Behavior

- The XIAO samples the optical sensor continuously at a configured 100 Hz and sends BLE heart-rate updates about once per second. The app saves **one valid point per minute** for its graph. Sampling only once a minute would miss threshold changes and sensor-contact status.
- The uploaded XIAO defaults to **Start 50 / Stop 40 BPM** on reboot and accepts whole-number settings with **40 ≤ Stop < Start ≤ 220**. The app's lowest valid Start is therefore 41 BPM. This cannot be lowered to 31 BPM from the app alone; the XIAO firmware would first need to change.
- **Auto** starts when valid BPM is strictly **above** Start and runs the pulse pattern for at least 60 seconds. After that it stops when BPM is strictly below Stop or readings are lost. **On** runs the pattern continuously, including after BLE disconnect. **Off** stops immediately. Changing thresholds does not restart the active timer. There is no 30-second low-BPM hold or cooldown in the uploaded Schematik program.
- The XIAO runs its chosen mode without the phone. A disconnected phone is not an emergency stop; use Off while connected or disconnect USB for the desk prototype. Test the motor only off-body.
- The app optionally reads **recent recorded workouts** from Apple Health, where Fitness/Watch records may appear. This is **not** a dependable live indication that another app's workout is running. Choose Off manually during exercise. Neither a recent workout nor its absence identifies anxiety.
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
3. Leave the current Schematik program on the XIAO while testing this app. The checked-in `firmware/MoodiWearable/MoodiWearable.ino` is an older, incompatible BLE implementation and would replace the working program if uploaded.
4. In the current Schematik program, Serial Monitor at **115200 baud** should scan I²C addresses `0x57` and `0x5A`; test contact, disconnect, and Off on the bench.
5. The uploaded program uses ERM/RTP values strong 90, soft 65, and clamp register 137, as reported by the user. Keep testing off-body and verify the motor rating before wearable use.

Seeed documents [D4/GPIO22 as SDA and D5/GPIO23 as SCL](https://wiki.seeedstudio.com/xiao_esp32c6_getting_started/). The [DRV2605L breakout reference](https://learn.adafruit.com/adafruit-drv2605-haptic-controller-breakout/pinouts) explains VIN, GND, I²C, and motor terminals; your purchased clone still needs visual checking. The [SparkFun library](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library) supports MAX30102. The [XIAO schematic](https://files.seeedstudio.com/wiki/SeeedStudio-XIAO-ESP32C6/XIAO-ESP32-C6_v1.0_SCH_PDF_24028.pdf) notes a 120 mA charging setting.

### Development dependencies on this Mac

Arduino CLI 1.5.1, Espressif `esp32:esp32` 3.3.12, SparkFun MAX3010x 1.1.2, Adafruit DRV2605 1.2.4, Adafruit BusIO 1.17.4, and NimBLE-Arduino 2.5.1 are installed. VS Code header paths are configured in `.vscode/c_cpp_properties.json`; reopen the folder or run **C/C++: Reset IntelliSense Database** if red include underlines persist. A real Arduino CLI compile is the authoritative check:

```sh
arduino-cli compile --fqbn esp32:esp32:XIAO_ESP32C6 firmware/MoodiWearable
```

The VS Code firmware tasks target the **older repo sketch**, not the Schematik program now on the board. Do not run its upload task unless intentionally replacing the current program. Editing iOS source does not change the XIAO.

## 2. iPhone app

This is a **native iOS app**, not a website: Core Bluetooth connects to XIAO and HealthKit provides permissioned access to workout records.

For first-time installation and a pass/fail device test, follow [the iPhone checklist](docs/IOS_DEVICE_CHECKLIST.md). No external Swift package is needed; full Xcode supplies the Apple frameworks.

1. Open `ios/Moodi.xcodeproj` in Xcode.
2. Select the `Moodi` target. Under **Signing & Capabilities**, choose your Apple development team and confirm **HealthKit** is enabled. The entitlement and permission strings are already included. Change the bundle identifier if your team requires it.
3. Run on a **physical iPhone** with Bluetooth on. Grant Bluetooth permission, then tap **Connect to XIAO**. The app connects to `CalmPulse`, reads Heart Rate Service `180D`, and discovers the new JSON control service. iOS Settings showing a connection does not mean this app has connected or discovered its controls.
4. Tap **Connect Health** to grant read access to Workouts, then **Refresh**. HealthKit may return no data even when read access was denied; the app therefore does not interpret “no workout” as “not exercising.”
5. Use the ± arrows to change Start and Reset BPM. Start accepts 41–220 BPM; Reset accepts 40 BPM up to one less than Start. The app sends settled values automatically and shows values reported by the wearable to confirm application. The single **Vibration on/off** switch sends Auto when on and Off when off; it never selects the firmware's indefinite manual On mode. Settings are BLE commands, not replacement program code.

### Home-screen widget

On **iOS 17 or later**, reinstall/run the updated app on your iPhone, then long-press the Home Screen, tap **Edit → Add Widget**, search for **moodi**, and choose **moodi controls** (small square). It shows a small Moodi logo, Start and Reset thresholds with ± controls, and a Connect button. The widget's controls run without opening the app: each threshold tap saves the new value and attempts a short Bluetooth connection, write, and status readback. **SYNCED** means the XIAO reported the requested numbers; **PENDING** means the phone saved them but the wearable has not confirmed them. Connect checks the wearable and retries any pending thresholds. This is a one-shot exchange, not a persistent Home Screen BLE connection. Bluetooth in widgets is still unverified on a physical iPhone with this XIAO; if the widget cannot reach CalmPulse, open the app and check its wearable-reported settings before relying on a change. The widget does not offer the vibration On/Off control; that remains in the app.

The app and widget use the App Group `group.studio.rehm.moodi.prototype`. In Xcode, keep **App Groups** enabled for both the Moodi and MoodiWidget targets and let automatic signing create matching profiles. If your Apple team cannot provision that group, Xcode will report a signing error and the widget cannot share settings until that capability is available. The main app still supports iOS 16, but the interactive widget requires iOS 17+.

The app uses foreground BLE. iOS may suspend it in the background; **XIAO-side sensing and stop rules continue**. It does not monitor another app's live workout session.

The app retries an unexpected BLE disconnect with increasing delay and displays the last disconnect reason. This can recover a transient drop, but repeated drops still need a hardware/firmware investigation. A revised copy of the Schematik code is included but **not uploaded**; the current XIAO still accepts indefinite manual On from other BLE clients. The Xcode build passes, but BLE connection, command acknowledgement, and live BPM still require a physical-iPhone test.

## Validation and unresolved hardware

- Confirm actual breakout VIN range, I²C pull-ups/levels, printed header order, and common ground on the delivered boards. Raw MAX30102 IC specifications are not the same as breakout-board VIN specifications.
- Obtain the exact DIANN motor rated voltage/current, startup current, and safe clamp. Measure the 3V3 rail under motor load before enabling output.
- The LiPo listing says “4.25 V / 100mAh” for maximum charging; the current unit should be **mA** and must be confirmed. The XIAO published charger setting is 120 mA. Until resolved: **USB only, no LiPo connection or on-body charging**.
- The prototype has no physical stop switch. A wearable revision needs local stop/power-off, insulated wiring, strain relief, sweat protection, and off-body charging.
- Elevated BPM has many causes. Neither the firmware nor Apple Health diagnoses anxiety. Uncertain contact or timing stops haptics rather than guessing.
- The current Schematik control characteristic has **no pairing protection**. Nearby BLE clients may send On/Off or threshold commands. Keep testing in a controlled setting and do not treat it as a safe wearable yet.

### Checks available on this Mac

```sh
clang++ -std=c++17 -Wall -Wextra -Werror firmware/tests/heart_logic_test.cpp -o /tmp/moodi-heart-test && /tmp/moodi-heart-test
plutil -lint ios/Moodi.xcodeproj/project.pbxproj ios/Moodi/Info.plist ios/Moodi/Moodi.entitlements
swiftc -frontend -parse ios/Moodi/*.swift
```

These checks validate source syntax and hardware-independent logic. They do **not** replace Arduino/Xcode builds, BLE pairing, or bench tests with the delivered parts.
