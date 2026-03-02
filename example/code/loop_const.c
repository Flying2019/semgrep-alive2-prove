#include <stdint.h>

int loop_const_dead_arith(int x, int y) {
  while (0) { x = (x * 3) - (y << 2); }
  return (x * 3) - (y << 2);
}

int loop_const_dead_bitmix(int x, int y) {
  while (0) { x = (x & y) | 7; }
  return (x & y) | 7;
}
