#include "kernel/types.h"
#include "user/user.h"

int main() {
  // 第一次 fork：仅父进程创建子进程 C1，C1 直接退出，不执行后续 fork
  int pid1 = fork();
  if (pid1 == 0) { // 子进程 C1 的逻辑
    printf("子进程 C1（%d）：不执行后续 fork，直接退出\n", getpid());
    exit(0); // 子进程退出，跳过第二次 fork
  } else if (pid1 < 0) { // fork 失败
    fprintf(2, "第一次 fork 失败\n");
    exit(1);
  }

  // 第二次 fork：仅父进程创建子进程 C2，C2 直接退出
  int pid2 = fork();
  if (pid2 == 0) { // 子进程 C2 的逻辑
    printf("子进程 C2（%d）：不执行后续 fork，直接退出\n", getpid());
    exit(0); // 子进程退出
  } else if (pid2 < 0) { // fork 失败
    fprintf(2, "第二次 fork 失败\n");
    exit(1);
  }

  // 父进程回收两个子进程
  int wpid1 = wait(0);
  printf("父进程回收子进程：%d\n", wpid1);
  int wpid2 = wait(0);
  printf("父进程回收子进程：%d\n", wpid2);

  exit(0);
}
