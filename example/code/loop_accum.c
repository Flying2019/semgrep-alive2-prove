#include <stdint.h>

int loop_accum_basic(int a, int n, int x) {
  for (int i = 0; i < n; i++) {
    a += x;
  }
  return a;
}

int loop_accum_no_brace(int a, int n, int x) {
  for (int i = 0; i < n; i++)
    a += x;
  return a;
}
