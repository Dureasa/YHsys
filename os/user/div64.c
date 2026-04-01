#include "kernel/types.h"

static uint64
udivmod64(uint64 n, uint64 d, uint64 *rem)
{
  uint64 q = 0;
  uint64 r = 0;

  if(d == 0){
    if(rem)
      *rem = 0;
    return 0;
  }

  for(int i = 63; i >= 0; i--){
    r = (r << 1) | ((n >> i) & 1ULL);
    if(r >= d){
      r -= d;
      q |= (1ULL << i);
    }
  }

  if(rem)
    *rem = r;
  return q;
}

unsigned long long
__udivdi3(unsigned long long n, unsigned long long d)
{
  return udivmod64(n, d, 0);
}

unsigned long long
__umoddi3(unsigned long long n, unsigned long long d)
{
  uint64 r;
  udivmod64(n, d, &r);
  return r;
}

static uint64
uabs64(long long x)
{
  if(x < 0)
    return (uint64)(-(x + 1)) + 1;
  return (uint64)x;
}

long long
__divdi3(long long n, long long d)
{
  int neg = ((n < 0) ^ (d < 0));
  uint64 q = udivmod64(uabs64(n), uabs64(d), 0);
  if(neg)
    return -(long long)q;
  return (long long)q;
}

long long
__moddi3(long long n, long long d)
{
  uint64 r;
  udivmod64(uabs64(n), uabs64(d), &r);
  if(n < 0)
    return -(long long)r;
  return (long long)r;
}