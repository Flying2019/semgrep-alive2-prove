#include <stdint.h>

int mul_add_simple(int x, int y) {
  return x * 2 + y;
}

int mul_add_nested(int x, int y, int z) {
  // (x * 2 + y) + z should still match the inner pattern
  return (x * 2 + y) + z;
}

int mul_add_paren(int x, int y) {
  // Parentheses preserved by Semgrep; parser supports them
  return (x * 2) + y;
}
