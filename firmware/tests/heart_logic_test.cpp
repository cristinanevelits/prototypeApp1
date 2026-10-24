#include "../MoodiWearable/HeartLogic.h"
#include <cassert>

int main() {
  HeartLogic logic;
  logic.update(1000, 110, true);
  assert(!logic.active);
  logic.update(5999, 110, true);
  assert(!logic.active);
  logic.update(6000, 110, true);
  assert(logic.active);
  assert(logic.level(6000, 80, 55) == 80);
  assert(logic.level(6150, 80, 55) == 0);
  assert(logic.level(6250, 80, 55) == 55);
  logic.update(7000, 85, true);
  logic.update(11999, 85, true);
  assert(logic.active);
  logic.update(12000, 85, true);
  assert(logic.active); // low BPM cannot end a valid response before one minute
  logic.update(65999, 85, true);
  assert(logic.active);
  logic.update(66000, 85, true);
  assert(!logic.active);

  logic.update(126000, 110, true);
  logic.update(131000, 110, true);
  assert(logic.active);
  logic.update(221000, 110, true);
  assert(logic.active);
  logic.update(371000, 110, true);
  assert(logic.active); // elevated BPM continues beyond one minute
  logic.update(371001, 90, true);
  assert(logic.active); // exactly the reset threshold is not below it
  logic.update(372000, 85, true);
  logic.update(390000, 110, true); // rising BPM cancels the low-BPM countdown
  logic.update(390001, 85, true);
  logic.update(420000, 85, true);
  assert(logic.active);
  logic.update(420001, 85, true);
  assert(!logic.active); // thirty continuous seconds below reset threshold

  logic.update(481000, 110, true);
  logic.update(486000, 110, true);
  assert(logic.active);
  logic.update(486100, 0, false);
  assert(logic.active); // lifting a finger cannot end the first minute
  assert(logic.level(487000, 80, 55) == 80);
  logic.update(545999, 0, false);
  assert(logic.active);
  logic.update(546000, 0, false);
  assert(!logic.active); // still no contact after one minute: stop

  logic.update(606000, 110, true);
  logic.update(611000, 110, true);
  assert(logic.active);
  logic.stopNow(611001);
  assert(!logic.active); // manual stop always overrides minimum duration

  logic.exerciseOverride = true;
  logic.update(700000, 120, true);
  logic.update(706000, 120, true);
  assert(!logic.active);
  assert(!logic.setThresholds(80, 100));
  assert(logic.setThresholds(105, 95));
}
