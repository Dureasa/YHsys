#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

void
test_binary(void)
{
  int fd;
  int pid;

  printf("1. binary semaphore test\n");
  fd = sem_create(1);
  if(fd < 0){
    printf("sem_create failed\n");
    exit(-1);
  }

  pid = fork();
  if(pid < 0){
    printf("fork failed\n");
    exit(-1);
  }

  if(pid == 0){
    sem_wait(fd);
    printf("  child in critical section\n");
    sem_post(fd);
    exit(0);
  } else {
    sem_wait(fd);
    printf("  parent in critical section\n");
    sem_post(fd);
    wait(0);
    sem_destroy(fd);
    printf("  binary test passed\n");
  }
}

void
test_counting(void)
{
  int fd;
  int i;

  printf("2. counting semaphore test\n");
  fd = sem_create(3);
  if(fd < 0){
    printf("sem_create failed\n");
    exit(-1);
  }

  for(i = 0; i < 3; i++){
    if(sem_wait(fd) < 0){
      printf("sem_wait failed\n");
      exit(-1);
    }
  }
  printf("  acquired all 3 resources\n");

  for(i = 0; i < 3; i++)
    sem_post(fd);
  printf("  released all 3 resources\n");

  sem_destroy(fd);
  printf("  counting test passed\n");
}

void
test_destroy(void)
{
  int fd;
  int pid;

  printf("3. sem_destroy test\n");
  fd = sem_create(0);
  if(fd < 0){
    printf("sem_create failed\n");
    exit(-1);
  }

  pid = fork();
  if(pid == 0){
    if(sem_wait(fd) < 0)
      printf("  child correctly got -1 from destroyed sem\n");
    exit(0);
  } else {
    sem_destroy(fd);
    wait(0);
    printf("  destroy test passed\n");
  }
}

int
main(void)
{
  printf("semaphore tests starting...\n");
  test_binary();
  test_counting();
  test_destroy();
  printf("all semaphore tests passed!\n");
  exit(0);
}
