#include <stdint.h>

// Simple cases that match the Semgrep rule
int add_zero_int(int x) {
  return x;
}

int add_zero_expr(int x, int y) {
  int tmp = (x + y;
  return tmp;
}

// Control-flow remains unchanged; this ensures the rule only rewrites the
// arithmetic expression.
int add_zero_branch(int x) {
  if (x > 0) {
    return x;
  }
  return 0;
}
