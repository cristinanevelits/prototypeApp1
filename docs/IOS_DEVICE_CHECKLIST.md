# iPhone build and device check

The iPhone app has no third-party Swift packages. SwiftUI, Charts, Core Bluetooth, and HealthKit are supplied by the iOS SDK in full Xcode. Arduino CLI and its libraries build the **XIAO firmware**, not the iPhone app.

## Before opening Xcode

- Install full Xcode from Apple and launch it once to finish installing components. Command Line Tools alone cannot build an iOS app.
- Use an iPhone with iOS 16 or later. The simulator cannot test this real BLE peripheral or the wearer's sensor contact.
- Keep the breadboard on USB power. Do **not** connect the LiPo yet; the motor settings still need independent electrical verification.
- Keep the October 26 Schematik `CalmPulse` program on the XIAO. Do **not** upload the separate `firmware/MoodiWearable/MoodiWearable.ino` from VS Code; its BLE control protocol is incompatible with this app.

## Build and run

1. Open `ios/Moodi.xcodeproj` in Xcode and select the **Moodi** scheme.
2. Under **Signing & Capabilities**, select your Apple development team and confirm the **HealthKit** capability remains enabled. If Xcode reports a bundle-ID conflict, replace `studio.rehm.moodi.prototype` with a unique identifier for your team.
3. Select your connected iPhone as the run destination. Accept any trust or Developer Mode prompts on the phone, then press **Run**.
4. Grant Bluetooth permission. Health access is optional and requested only when you tap **Connect Health**.

## First functional test

1. With the USB-powered XIAO nearby, tap **Connect to XIAO**. The app finds `CalmPulse`, discovers Heart Rate `180D` and the `8A7E...` control service, and shows **Connected**. If it says **pulse only**, verify the new Schematik program is actually flashed.
2. Put the MAX30102 optical face against skin. A plausible BPM should appear once enough clean beats have been collected. Removing it should clear the number; `0` must never appear as a measured pulse.
3. Use the ± arrows to set valid Start and Reset values (for example 50 and 40). Wait briefly, then confirm the wearable-reported values match and the pending label clears. The currently uploaded program rejects a Reset below 40 BPM.
4. Turn **Vibration on/off** off and on; verify the reported firmware mode follows Off and Auto. The app deliberately does not expose manual On because that firmware mode can run indefinitely after Bluetooth disconnect.
5. Tap **Connect Health**, grant workout read access if desired, and tap **Refresh**. A recorded workout may appear. No result does **not** mean the user is not exercising.
6. Disconnect and reconnect. The XIAO should advertise again. Leave the app foregrounded for this prototype; background BLE behavior is not implemented.

The Schematik program can run the motor. Test it only off-body, and verify the motor's rated voltage/current before wearable use. Do not try to force a high heart rate to test the threshold logic. The tests in `firmware/tests/` apply to the older repo sketch, not the Schematik program.

The current Schematik command characteristic has no BLE pairing protection. Treat this as a supervised prototype, not a secure wearable.

If Xcode reports a build, signing, pairing, or permission error, record the exact message and device/iOS version before changing settings. An actual Xcode build and iPhone test are still required to call this app working on iOS.
