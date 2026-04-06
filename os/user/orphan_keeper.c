#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"

static int
is_dir_mode(const char *prog)
{
  const char *p = prog;
  while(*p)
    p++;
  while(p > prog && p[-1] != '/')
    p--;
  return strcmp((char*)p, "dorphan") == 0;
}

int
main(int argc, char **argv)
{
  char *s = argv[0];

  if(is_dir_mode(argv[0])){
    if(mkdir("dd") != 0){
      printf("%s: mkdir dd failed\n", s);
      exit(1);
    }

    if(chdir("dd") != 0){
      printf("%s: chdir dd failed\n", s);
      exit(1);
    }

    if(unlink("../dd") < 0){
      printf("%s: unlink failed\n", s);
      exit(1);
    }

    printf("wait for kill and reclaim\n");
    for(;;)
      pause(1000);
  }

  int fd;
  struct stat st;
  char *ff = "file0";

  fd = open(ff, O_CREATE|O_WRONLY);
  if(fd < 0){
    printf("%s: open failed\n", s);
    exit(1);
  }
  if(fstat(fd, &st) < 0){
    fprintf(2, "%s: cannot stat %s\n", s, ff);
    exit(1);
  }
  if(unlink(ff) < 0){
    printf("%s: unlink failed\n", s);
    exit(1);
  }
  if(open(ff, O_RDONLY) != -1){
    printf("%s: open succeeded\n", s);
    exit(1);
  }

  printf("wait for kill and reclaim %d\n", st.ino);
  for(;;)
    pause(1000);
}
