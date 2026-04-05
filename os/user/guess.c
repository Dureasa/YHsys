#include "kernel/types.h"
#include "user/user.h"

static uint seed;

static int
rand_range(int n)
{
  seed = seed * 1103515245u + 12345u + (uint)uptime();
  return (seed >> 16) % n;
}

int
main(void)
{
  char buf[32];
  int tries = 0;
  int target;

  seed = (uint)uptime() ^ ((uint)getpid() << 8);
  target = rand_range(99) + 1;

  printf("YHsys guess: pick a number in [1, 99], 'q' to quit.\n");
  while(1){
    printf("guess[%d]> ", tries + 1);
    memset(buf, 0, sizeof(buf));
    gets(buf, sizeof(buf));
    if(buf[0] == 0)
      break;
    if(buf[0] == 'q' || buf[0] == 'Q'){
      printf("bye, target was %d\n", target);
      break;
    }

    int g = atoi(buf);
    if(g < 1 || g > 99){
      printf("range error, use 1..99\n");
      continue;
    }

    tries++;
    if(g == target){
      printf("hit! solved in %d tries.\n", tries);
      return 0;
    }
    if(g < target)
      printf("too low\n");
    else
      printf("too high\n");

    if(tries >= 12){
      printf("round over, target was %d\n", target);
      break;
    }
  }

  return 0;
}
