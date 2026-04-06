#include "kernel/types.h"
#include "user/user.h"

static void
print_logo(void)
{
  printf("  __   __ _   _                \n");
  printf("  \\ \\ / /| | | |___  _   _ ___ \n");
  printf("   \\ V / | |_| / __|| | | / __|\n");
  printf("    | |  |  _  \\__ \\ |_| \\\\__ \\\n");
  printf("    |_|  |_| |_||___/\\__, ||___/\n");
  printf("                      |___/      \n");
}

int
main(int argc, char **argv)
{
  print_logo();
  printf("YHsys RV32-UP shell tools\n");

  if(argc > 1){
    printf("message: ");
    for(int i = 1; i < argc; i++){
      printf("%s", argv[i]);
      if(i + 1 < argc)
        printf(" ");
    }
    printf("\n");
  } else {
    printf("tip: run 'guess' or 'rps' for mini games.\n");
  }
  return 0;
}
