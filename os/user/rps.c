#include "kernel/types.h"
#include "user/user.h"

static uint seed;

static int
rand3(void)
{
  seed = seed * 1664525u + 1013904223u + (uint)uptime();
  return (seed >> 20) % 3;
}

static const char *
name_of(int v)
{
  if(v == 0)
    return "rock";
  if(v == 1)
    return "paper";
  return "scissors";
}

static int
decode(char c)
{
  if(c == 'r' || c == 'R')
    return 0;
  if(c == 'p' || c == 'P')
    return 1;
  if(c == 's' || c == 'S')
    return 2;
  return -1;
}

int
main(void)
{
  char buf[16];
  int win = 0;
  int lose = 0;
  int draw = 0;

  seed = (uint)uptime() ^ ((uint)getpid() << 4);

  printf("YHsys rps: r/p/s, q to quit.\n");
  for(int round = 1; round <= 8; round++){
    printf("round %d > ", round);
    memset(buf, 0, sizeof(buf));
    gets(buf, sizeof(buf));
    if(buf[0] == 0 || buf[0] == 'q' || buf[0] == 'Q')
      break;

    int me = decode(buf[0]);
    if(me < 0){
      printf("invalid input, use r/p/s\n");
      round--;
      continue;
    }

    int cpu = rand3();
    printf("you=%s cpu=%s ", name_of(me), name_of(cpu));

    if(me == cpu){
      draw++;
      printf("=> draw\n");
      continue;
    }

    if((me == 0 && cpu == 2) || (me == 1 && cpu == 0) || (me == 2 && cpu == 1)){
      win++;
      printf("=> win\n");
    } else {
      lose++;
      printf("=> lose\n");
    }
  }

  printf("score: win=%d lose=%d draw=%d\n", win, lose, draw);
  if(win > lose)
    printf("result: champion\n");
  else if(win < lose)
    printf("result: keep training\n");
  else
    printf("result: tie\n");

  return 0;
}
