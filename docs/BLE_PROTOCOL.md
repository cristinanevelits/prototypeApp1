# moodi BLE protocol · version 1

The XIAO advertises as `moodi`, with the custom 128-bit service UUID in the advertisement. The standard Heart Rate service is discoverable after connection. UUIDs are implemented in both `firmware/MoodiWearable/MoodiWearable.ino` and `ios/Moodi/MoodiProtocol.swift`.

| Service / characteristic | UUID | Purpose |
|---|---|---|
| Heart Rate service | `180D` | Standard heart-rate service |
| Heart Rate Measurement | `2A37` | Read + notify, about 1 Hz |
| moodi service | `8F941100-B6B1-4F96-9F4D-356DB1FE7A10` | Custom control/status |
| Status | `8F941101-B6B1-4F96-9F4D-356DB1FE7A10` | Read + notify, about 1 Hz |
| Control | `8F941102-B6B1-4F96-9F4D-356DB1FE7A10` | Encrypted write with response |

Heart Rate Measurement is two bytes: flags `0x06` and 8-bit BPM when current reading is valid; flags `0x04` and BPM `0` otherwise. These are the standard contact-supported/contact-detected bits. Never plot zero as a measured heart rate.

Status is five bytes: `[version=1, flags, bpm, startBpm, stopBpm]`. Flags: bit `0` valid reading, `1` motor active, `2` automatic mode, `3` exercise override, `4` sensor found, `5` driver found, `6` motor hardware approved/unlocked. A threshold decision with output locked does not set motor-active.

Control byte arrays:

| Bytes | Action |
|---|---|
| `[0x01, 0 or 1]` | Disable/enable automatic response |
| `[0x02, 0 or 1]` | Disable/enable manual exercise override |
| `[0x03, startBpm, stopBpm]` | Set thresholds; start 50–200, stop 40 to less than start |
| `[0x04]` | Stop now and disable automatic response |

Thresholds and overrides are RAM-only and reset on reboot. The phone is optional for autonomous threshold behavior. No raw PPG, location, identity, or HealthKit data is sent to the XIAO.
