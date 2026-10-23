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
  assert(!logic.active);

  logic.update(73000, 110, true);
  logic.update(78000, 110, true);
  assert(logic.active);
  logic.update(88000, 110, true);
  assert(!logic.active); // ten-second burst limit

  logic.update(150000, 110, true);
  logic.update(155000, 110, true);
  assert(logic.active);
  logic.update(155100, 0, false);
  assert(!logic.active); // lost contact always stops

  logic.exerciseOverride = true;
  logic.update(300000, 120, true);
  logic.update(306000, 120, true);
  assert(!logic.active);
  assert(!logic.setThresholds(80, 100));
  assert(logic.setThresholds(105, 95));
}
