#pragma once

#include <stdint.h>

// Hardware-independent decision logic. BPM elevation is NOT an anxiety diagnosis.
class HeartLogic {
 public:
  uint8_t startBpm = 100;
  uint8_t stopBpm = 90;
  bool automatic = true;
  bool exerciseOverride = false;
  bool active = false;

  void stopNow(uint32_t now) {
    active = false;
    highPending_ = false;
    lowPending_ = false;
    cooldownUntil_ = now + 60000UL;
  }

  bool setThresholds(uint8_t start, uint8_t stop) {
    if (start < 50 || start > 200 || stop < 40 || stop >= start) return false;
    startBpm = start;
    stopBpm = stop;
    highPending_ = false;
    lowPending_ = false;
    return true;
  }

  void update(uint32_t now, uint8_t bpm, bool valid) {
    if (!valid || !automatic || exerciseOverride) {
      active = false;
      highPending_ = false;
      lowPending_ = false;
      return;
    }

    if (active) {
      // Never vibrate indefinitely, even if the reading stays high.
      if (now - burstStarted_ >= 10000UL) {
        stopNow(now);
        return;
      }
      if (bpm <= stopBpm) {
        if (!lowPending_) { lowPending_ = true; lowSince_ = now; }
        if (now - lowSince_ >= 5000UL) stopNow(now);
      } else {
        lowPending_ = false;
      }
      return;
    }

    if (static_cast<int32_t>(now - cooldownUntil_) < 0) return;
    if (bpm >= startBpm) {
      if (!highPending_) { highPending_ = true; highSince_ = now; }
      if (now - highSince_ >= 5000UL) {
        active = true;
        burstStarted_ = now;
        highPending_ = false;
      }
    } else {
      highPending_ = false;
    }
  }

  // 60-BPM-inspired double beat. Output is a bounded RTP level, not a voltage.
  uint8_t level(uint32_t now, uint8_t strong, uint8_t soft) const {
    if (!active) return 0;
    const uint32_t phase = (now - burstStarted_) % 1000UL;
    if (phase < 110) return strong;
    if (phase >= 230 && phase < 310) return soft;
    return 0;
  }

 private:
  bool highPending_ = false;
  bool lowPending_ = false;
  uint32_t highSince_ = 0;
  uint32_t lowSince_ = 0;
  uint32_t burstStarted_ = 0;
  uint32_t cooldownUntil_ = 0;
};

