// Software multiply and divide for user programs on the teaching core built without the M extension.
//
// gcc for RV64 without M calls the libgcc entry points below for every integer `*`, `/` and `%` whose
// operands are not constants (32-bit operands are widened and go through the 64-bit routines too).
// xv6 links with -nostdlib and no libgcc, so the routines live here, in the xv6 user library, where a
// reader can see exactly what the hardware is being asked to do. When the M extension is added the
// compiler emits mul/div/rem instead and this file simply stops being referenced.
//
// There is no integer `*`, `/` or `%` anywhere in this file: each one would compile into a call back
// into this file. Division semantics follow the RISC-V M extension so that a program behaves the same
// with and without hardware divide: x / 0 = all ones, x % 0 = x, MIN / -1 = MIN, MIN % -1 = 0.
#include "kernel/types.h"

static unsigned long long
umul64(unsigned long long a, unsigned long long b)
{
  unsigned long long r = 0;
  while (b != 0) {
    if (b & 1)
      r += a;
    a <<= 1;
    b >>= 1;
  }
  return r;
}

// restoring division, one quotient bit per step, most significant first
static unsigned long long
udivmod64(unsigned long long n, unsigned long long d, unsigned long long *rem)
{
  unsigned long long q = 0, r = 0;
  int i;

  if (d == 0) {
    *rem = n;
    return ~0ULL;
  }
  for (i = 63; i >= 0; i--) {
    r = (r << 1) | ((n >> i) & 1);
    if (r >= d) {
      r -= d;
      q |= 1ULL << i;
    }
  }
  *rem = r;
  return q;
}

// two's complement: the low 64 bits of a signed product equal those of the unsigned one
long long
__muldi3(long long a, long long b)
{
  return (long long)umul64((unsigned long long)a, (unsigned long long)b);
}

unsigned long long
__udivdi3(unsigned long long n, unsigned long long d)
{
  unsigned long long r;
  return udivmod64(n, d, &r);
}

unsigned long long
__umoddi3(unsigned long long n, unsigned long long d)
{
  unsigned long long r;
  udivmod64(n, d, &r);
  return r;
}

// negate through unsigned arithmetic so that the most negative value does not overflow
static unsigned long long
uabs64(long long x)
{
  return x < 0 ? 0ULL - (unsigned long long)x : (unsigned long long)x;
}

long long
__divdi3(long long a, long long b)
{
  unsigned long long r, q;

  if (b == 0)
    return -1LL;
  q = udivmod64(uabs64(a), uabs64(b), &r);
  return ((a < 0) != (b < 0)) ? (long long)(0ULL - q) : (long long)q;
}

long long
__moddi3(long long a, long long b)
{
  unsigned long long r;

  if (b == 0)
    return a;
  udivmod64(uabs64(a), uabs64(b), &r);
  return a < 0 ? (long long)(0ULL - r) : (long long)r;
}

// 32-bit entry points, in case a toolchain uses them instead of widening
int
__mulsi3(int a, int b)
{
  return (int)umul64((unsigned long long)(unsigned int)a, (unsigned long long)(unsigned int)b);
}

int
__divsi3(int a, int b)
{
  return (int)__divdi3(a, b);
}

int
__modsi3(int a, int b)
{
  return (int)__moddi3(a, b);
}

unsigned int
__udivsi3(unsigned int a, unsigned int b)
{
  return (unsigned int)__udivdi3(a, b);
}

unsigned int
__umodsi3(unsigned int a, unsigned int b)
{
  return (unsigned int)__umoddi3(a, b);
}
