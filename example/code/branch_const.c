#include <stdint.h>

int branch_true_a(int x, int y) {
  if (1) {
    return x + y;
  } else {
    return x - y;
  }
}

int branch_false_a(int x, int y) {
  if (0) {
    return x + 1;
  } else {
    return y + 1;
  }
}
