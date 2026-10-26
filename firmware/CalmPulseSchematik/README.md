# CalmPulse Schematik copy — not yet uploaded

`CalmPulseSchematik.ino` starts from the complete sketch the user pasted on October 26. It is **not** the older `MoodiWearable` sketch and has **not** been flashed to the XIAO from this repo.

Changes from that pasted sketch:

- The only accepted modes are `auto` and `off`. A `{"mode":"on"}` command is rejected with `manual_on_disabled`, so vibration cannot be left in the sensor-independent, indefinite mode.
- Status includes `contact` and `valid` booleans for diagnosing whether the sensor still thinks it has a reading after the finger is removed.
- JSON status generation is limited to 5 Hz instead of every 1 ms. Heart-rate notifications still occur about once per second.

Auto behavior is otherwise unchanged: it runs at least 60 seconds once triggered, then stops if the reading is invalid or BPM is below Stop. If it continues after the finger is removed in Auto, inspect `contact`, `valid`, and the raw IR level before changing the sensor threshold; ambient conditions and module variants can affect that threshold.

This copy has **not** been compiled here because ArduinoJson is not installed in the local Arduino CLI library set. Compile and inspect it in Schematik before any optional upload. Keep testing off-body; the motor settings are user-reported, not independently verified.
