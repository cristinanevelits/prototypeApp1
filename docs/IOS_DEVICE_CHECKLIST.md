# iPhone build and device check

The iPhone app has no third-party Swift packages. SwiftUI, Charts, Core Bluetooth, and HealthKit are supplied by the iOS SDK in full Xcode. Arduino CLI and its libraries build the **XIAO firmware**, not the iPhone app.

## Before opening Xcode

- Install full Xcode from Apple and launch it once to finish installing components. Command Line Tools alone cannot build an iOS app.
- Use an iPhone with iOS 16 or later. The simulator cannot test this real BLE peripheral or the wearer's sensor contact.
- Keep the breadboard on USB power. Do **not** connect the LiPo yet; motor output remains locked in firmware pending electrical verification.
- Compile and upload `firmware/MoodiWearable/MoodiWearable.ino` to the XIAO ESP32-C6. The app cannot discover a board that is running unrelated firmware.

## Build and run

1. Open `ios/Moodi.xcodeproj` in Xcode and select the **Moodi** scheme.
2. Under **Signing & Capabilities**, select your Apple development team and confirm the **HealthKit** capability remains enabled. If Xcode reports a bundle-ID conflict, replace `studio.rehm.moodi.prototype` with a unique identifier for your team.
3. Select your connected iPhone as the run destination. Accept any trust or Developer Mode prompts on the phone, then press **Run**.
4. Grant Bluetooth permission. Health access is optional and requested only when you tap **Connect Health**.

## First functional test

1. With the USB-powered XIAO nearby, tap **Connect to XIAO**. The app should find `moodi`, discover both services, and show **Connected**. Secure controls may prompt for Bluetooth pairing.
2. Put the MAX30102 optical face against skin. A plausible BPM should appear once enough clean beats have been collected. Removing it should clear the number; `0` must never appear as a measured pulse.
3. Change the two thresholds and tap **Send thresholds**. Check that the displayed settings settle to the values reported back by the XIAO.
4. Switch on **I'm exercising**. The device status should reflect the override and suppress automatic response. Switch it off again.
5. Tap **Connect Health**, grant workout read access if desired, and tap **Refresh**. A recorded workout may appear. No result does **not** mean the user is not exercising.
6. Disconnect and reconnect. The XIAO should advertise again. Leave the app foregrounded for this prototype; background BLE behavior is not implemented.

The motor will **not** vibrate in this build. That is intentional: its electrical rating and safe DRV2605L settings still need an off-body bench check. Do not try to force a high heart rate to test the threshold logic; the hardware-independent timing and stop rules have automated tests in `firmware/tests/`.

If Xcode reports a build, signing, pairing, or permission error, record the exact message and device/iOS version before changing settings. An actual Xcode build and iPhone test are still required to call this app working on iOS.
