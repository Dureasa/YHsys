#include "types.h"
#include "riscv.h"
#include "defs.h"
#include "param.h"
#include "spinlock.h"
#include "sleeplock.h"
#include "fs.h"
#include "proc.h"
#include "file.h"
#include "syscall.h"

struct semaphore {
  struct spinlock lock;
  int value;
  int ref_count;
  int destroyed;
};

static struct semaphore*
sem_alloc(int value)
{
  struct semaphore *s;

  s = (struct semaphore*)kalloc();
  if(s == 0)
    return 0;

  s->value = value;
  s->ref_count = 0;
  s->destroyed = 0;
  initlock(&s->lock, "sem");

  return s;
}

void
sem_close(struct semaphore *s)
{
  acquire(&s->lock);
  s->ref_count--;
  if(s->ref_count > 0) {
    release(&s->lock);
    return;
  }
  release(&s->lock);
  kfree((void*)s);
}

uint64
sys_sem_create(void)
{
  int value;
  int fd;
  struct file *f;
  struct semaphore *s;
  struct proc *p = myproc();

  argint(0, &value);
  if(value < 0)
    return -1;

  if((f = filealloc()) == 0)
    return -1;

  if((s = sem_alloc(value)) == 0) {
    fileclose(f);
    return -1;
  }

  for(fd = 0; fd < NOFILE; fd++) {
    if(p->ofile[fd] == 0) {
      p->ofile[fd] = f;
      break;
    }
  }
  if(fd >= NOFILE) {
    fileclose(f);
    return -1;
  }

  f->type = FD_SEM;
  f->readable = 1;
  f->writable = 1;
  f->sem = s;
  acquire(&s->lock);
  s->ref_count++;
  release(&s->lock);

  return fd;
}

uint64
sys_sem_wait(void)
{
  int fd;
  struct file *f;
  struct proc *p = myproc();
  struct semaphore *s;

  argint(0, &fd);
  if(fd < 0 || fd >= NOFILE || (f = p->ofile[fd]) == 0)
    return -1;
  if(f->type != FD_SEM)
    return -1;

  s = f->sem;
  acquire(&s->lock);

  while(s->value <= 0) {
    if(s->destroyed || killed(p)) {
      release(&s->lock);
      return -1;
    }
    sleep(s, &s->lock);
  }

  s->value--;
  release(&s->lock);
  return 0;
}

uint64
sys_sem_post(void)
{
  int fd;
  struct file *f;
  struct proc *p = myproc();
  struct semaphore *s;

  argint(0, &fd);
  if(fd < 0 || fd >= NOFILE || (f = p->ofile[fd]) == 0)
    return -1;
  if(f->type != FD_SEM)
    return -1;

  s = f->sem;
  acquire(&s->lock);
  s->value++;
  wakeup(s);
  release(&s->lock);
  return 0;
}

uint64
sys_sem_destroy(void)
{
  int fd;
  struct file *f;
  struct proc *p = myproc();
  struct semaphore *s;

  argint(0, &fd);
  if(fd < 0 || fd >= NOFILE || (f = p->ofile[fd]) == 0)
    return -1;
  if(f->type != FD_SEM)
    return -1;

  s = f->sem;
  acquire(&s->lock);
  s->destroyed = 1;
  wakeup(s);
  release(&s->lock);

  p->ofile[fd] = 0;
  fileclose(f);
  return 0;
}
