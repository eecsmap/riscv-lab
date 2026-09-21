#include "types.h"

void *
memset(void *dst, int c, uint n)
{
  char *cdst = (char *)dst;
  uint i = 0;

  // Rocket port: upstream stores one byte per iteration, which on this
  // 25MHz in-order core measures at ~5 cycles per byte -- so zeroing a 4KB
  // page costs ~20k cycles. That is not a memory-bandwidth limit: it only
  // moves 0.19 bytes/cycle, orders of magnitude below what the AXI HP port
  // to the PS's DDR can carry. It is simply the loop.
  //
  // Store 8 bytes at a time instead. Note the alignment handling is not
  // optional here: a misaligned load/store is one of the exceptions
  // rocket-chip refuses to delegate (see kernelvec.S), so getting it wrong
  // traps to M-mode rather than faulting cleanly.
  if (n >= 16) {
    while ((((uint64)cdst + i) & 7) != 0) {
      cdst[i] = c;
      i++;
    }
    uint64 word = (uint64)(unsigned char)c;
    word |= word << 8;
    word |= word << 16;
    word |= word << 32;
    for (; i + 8 <= n; i += 8)
      *(uint64 *)(cdst + i) = word;
  }
  for (; i < n; i++)
    cdst[i] = c;

  return dst;
}

int
memcmp(const void *v1, const void *v2, uint n)
{
  const uchar *s1, *s2;

  s1 = v1;
  s2 = v2;
  while (n-- > 0) {
    if (*s1 != *s2)
      return *s1 - *s2;
    s1++, s2++;
  }

  return 0;
}

void *
memmove(void *dst, const void *src, uint n)
{
  const char *s;
  char *d;

  if (n == 0)
    return dst;

  s = src;
  d = dst;
  if (s < d && s + n > d) {
    // Overlapping and moving up: must copy backwards. Left as a byte loop;
    // it is the rare case.
    s += n;
    d += n;
    while (n-- > 0)
      *--d = *--s;
    return dst;
  }

  // Rocket port: 8 bytes per iteration rather than one, for the same reason
  // as memset() above. Only when source and destination share an alignment
  // phase, since misaligned accesses trap to M-mode on this core. This is
  // the hot path for uvmcopy() (a page per fork) and readi().
  if (n >= 16 && ((((uint64)s) ^ ((uint64)d)) & 7) == 0) {
    while ((((uint64)d) & 7) != 0 && n > 0) {
      *d++ = *s++;
      n--;
    }
    while (n >= 8) {
      *(uint64 *)d = *(const uint64 *)s;
      d += 8;
      s += 8;
      n -= 8;
    }
  }
  while (n-- > 0)
    *d++ = *s++;

  return dst;
}

// memcpy exists to placate GCC.  Use memmove.
void *
memcpy(void *dst, const void *src, uint n)
{
  return memmove(dst, src, n);
}

int
strncmp(const char *p, const char *q, uint n)
{
  while (n > 0 && *p && *p == *q)
    n--, p++, q++;
  if (n == 0)
    return 0;
  return (uchar)*p - (uchar)*q;
}

char *
strncpy(char *s, const char *t, int n)
{
  char *os;

  os = s;
  while (n-- > 0 && (*s++ = *t++) != 0)
    ;
  while (n-- > 0)
    *s++ = 0;
  return os;
}

// Like strncpy but guaranteed to NUL-terminate.
char *
safestrcpy(char *s, const char *t, int n)
{
  char *os;

  os = s;
  if (n <= 0)
    return os;
  while (--n > 0 && (*s++ = *t++) != 0)
    ;
  *s = 0;
  return os;
}

int
strlen(const char *s)
{
  int n;

  for (n = 0; s[n]; n++)
    ;
  return n;
}
