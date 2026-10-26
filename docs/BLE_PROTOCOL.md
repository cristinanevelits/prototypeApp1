# CalmPulse BLE protocol · Schematik firmware

The currently uploaded XIAO program advertises as `CalmPulse` with Heart Rate service `180D`. The app discovers the custom service after connection. This protocol is defined by the user's Schematik program pasted on October 26; it is **not** the separate repository sketch's older binary command protocol.

| Service / characteristic | UUID | Purpose |
|---|---|---|
| Heart Rate service | `180D` | Standard heart-rate service |
| Heart Rate Measurement | `2A37` | Read + notify, about 1 Hz |
| Control service | `8A7E1000-6F34-4C9A-9F30-2B739074F001` | Custom control/status |
| Command | `8A7E1001-6F34-4C9A-9F30-2B739074F001` | UTF-8 JSON write with response; no pairing protection |
| Status | `8A7E1002-6F34-4C9A-9F30-2B739074F001` | UTF-8 JSON read + notify |

Heart Rate Measurement is two bytes: flags `0x06` and 8-bit BPM when current reading is valid; flags `0x04` and BPM `0` otherwise. These are the standard contact-supported/contact-detected bits. Never plot zero as a measured heart rate.

Status JSON fields: `seq`, `start`, `stop`, `mode`, `active`, `driver`, `remaining`, `error`. `seq` increments for every received command; `error` is empty on success or a rejection code such as `invalid_threshold`.

Command JSON objects:

| JSON | Action |
|---|---|
| `{"mode":"auto"}` | Start automatically above threshold; minimum 60 seconds |
| `{"mode":"on"}` | Accepted by the program currently uploaded on October 26; runs continuously, including through BLE disconnection. The app never sends this. The unflashed `firmware/CalmPulseSchematik/` copy rejects it. |
| `{"mode":"off"}` | Stop immediately |
| `{"start":100,"stop":90}` | Set both thresholds; 40 ≤ stop < start ≤ 220 |

Thresholds and mode are RAM-only and reset on XIAO reboot. The app saves threshold choices locally and resends them on reconnection. It does not automatically re-enable manual On after a new app session. The phone is optional for autonomous Auto behavior. No raw PPG, location, identity, or HealthKit data is sent to the XIAO.
