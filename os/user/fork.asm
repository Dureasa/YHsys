
user/_fork：     文件格式 elf64-littleriscv


Disassembly of section .text:

0000000000000000 <main>:
#include "kernel/types.h"
#include "user/user.h"

int main() {
   0:	1141                	addi	sp,sp,-16
   2:	e406                	sd	ra,8(sp)
   4:	e022                	sd	s0,0(sp)
   6:	0800                	addi	s0,sp,16
  // 第一次 fork：仅父进程创建子进程 C1，C1 直接退出，不执行后续 fork
  int pid1 = fork();
   8:	348000ef          	jal	350 <fork>
  if (pid1 == 0) { // 子进程 C1 的逻辑
   c:	cd1d                	beqz	a0,4a <main+0x4a>
    printf("子进程 C1（%d）：不执行后续 fork，直接退出\n", getpid());
    exit(0); // 子进程退出，跳过第二次 fork
  } else if (pid1 < 0) { // fork 失败
   e:	04054a63          	bltz	a0,62 <main+0x62>
    fprintf(2, "第一次 fork 失败\n");
    exit(1);
  }

  // 第二次 fork：仅父进程创建子进程 C2，C2 直接退出
  int pid2 = fork();
  12:	33e000ef          	jal	350 <fork>
  if (pid2 == 0) { // 子进程 C2 的逻辑
  16:	c125                	beqz	a0,76 <main+0x76>
    printf("子进程 C2（%d）：不执行后续 fork，直接退出\n", getpid());
    exit(0); // 子进程退出
  } else if (pid2 < 0) { // fork 失败
  18:	06054b63          	bltz	a0,8e <main+0x8e>
    fprintf(2, "第二次 fork 失败\n");
    exit(1);
  }

  // 父进程回收两个子进程
  int wpid1 = wait(0);
  1c:	4501                	li	a0,0
  1e:	342000ef          	jal	360 <wait>
  22:	85aa                	mv	a1,a0
  printf("父进程回收子进程：%d\n", wpid1);
  24:	00001517          	auipc	a0,0x1
  28:	9dc50513          	addi	a0,a0,-1572 # a00 <malloc+0x1aa>
  2c:	772000ef          	jal	79e <printf>
  int wpid2 = wait(0);
  30:	4501                	li	a0,0
  32:	32e000ef          	jal	360 <wait>
  36:	85aa                	mv	a1,a0
  printf("父进程回收子进程：%d\n", wpid2);
  38:	00001517          	auipc	a0,0x1
  3c:	9c850513          	addi	a0,a0,-1592 # a00 <malloc+0x1aa>
  40:	75e000ef          	jal	79e <printf>

  exit(0);
  44:	4501                	li	a0,0
  46:	312000ef          	jal	358 <exit>
    printf("子进程 C1（%d）：不执行后续 fork，直接退出\n", getpid());
  4a:	38e000ef          	jal	3d8 <getpid>
  4e:	85aa                	mv	a1,a0
  50:	00001517          	auipc	a0,0x1
  54:	90050513          	addi	a0,a0,-1792 # 950 <malloc+0xfa>
  58:	746000ef          	jal	79e <printf>
    exit(0); // 子进程退出，跳过第二次 fork
  5c:	4501                	li	a0,0
  5e:	2fa000ef          	jal	358 <exit>
    fprintf(2, "第一次 fork 失败\n");
  62:	00001597          	auipc	a1,0x1
  66:	92e58593          	addi	a1,a1,-1746 # 990 <malloc+0x13a>
  6a:	4509                	li	a0,2
  6c:	708000ef          	jal	774 <fprintf>
    exit(1);
  70:	4505                	li	a0,1
  72:	2e6000ef          	jal	358 <exit>
    printf("子进程 C2（%d）：不执行后续 fork，直接退出\n", getpid());
  76:	362000ef          	jal	3d8 <getpid>
  7a:	85aa                	mv	a1,a0
  7c:	00001517          	auipc	a0,0x1
  80:	92c50513          	addi	a0,a0,-1748 # 9a8 <malloc+0x152>
  84:	71a000ef          	jal	79e <printf>
    exit(0); // 子进程退出
  88:	4501                	li	a0,0
  8a:	2ce000ef          	jal	358 <exit>
    fprintf(2, "第二次 fork 失败\n");
  8e:	00001597          	auipc	a1,0x1
  92:	95a58593          	addi	a1,a1,-1702 # 9e8 <malloc+0x192>
  96:	4509                	li	a0,2
  98:	6dc000ef          	jal	774 <fprintf>
    exit(1);
  9c:	4505                	li	a0,1
  9e:	2ba000ef          	jal	358 <exit>

00000000000000a2 <start>:
//
// wrapper so that it's OK if main() does not call exit().
//
void
start(int argc, char **argv)
{
  a2:	1141                	addi	sp,sp,-16
  a4:	e406                	sd	ra,8(sp)
  a6:	e022                	sd	s0,0(sp)
  a8:	0800                	addi	s0,sp,16
  int r;
  extern int main(int argc, char **argv);
  r = main(argc, argv);
  aa:	f57ff0ef          	jal	0 <main>
  exit(r);
  ae:	2aa000ef          	jal	358 <exit>

00000000000000b2 <strcpy>:
}

char*
strcpy(char *s, const char *t)
{
  b2:	1141                	addi	sp,sp,-16
  b4:	e406                	sd	ra,8(sp)
  b6:	e022                	sd	s0,0(sp)
  b8:	0800                	addi	s0,sp,16
  char *os;

  os = s;
  while((*s++ = *t++) != 0)
  ba:	87aa                	mv	a5,a0
  bc:	0585                	addi	a1,a1,1
  be:	0785                	addi	a5,a5,1
  c0:	fff5c703          	lbu	a4,-1(a1)
  c4:	fee78fa3          	sb	a4,-1(a5)
  c8:	fb75                	bnez	a4,bc <strcpy+0xa>
    ;
  return os;
}
  ca:	60a2                	ld	ra,8(sp)
  cc:	6402                	ld	s0,0(sp)
  ce:	0141                	addi	sp,sp,16
  d0:	8082                	ret

00000000000000d2 <strcmp>:

int
strcmp(const char *p, const char *q)
{
  d2:	1141                	addi	sp,sp,-16
  d4:	e406                	sd	ra,8(sp)
  d6:	e022                	sd	s0,0(sp)
  d8:	0800                	addi	s0,sp,16
  while(*p && *p == *q)
  da:	00054783          	lbu	a5,0(a0)
  de:	cb91                	beqz	a5,f2 <strcmp+0x20>
  e0:	0005c703          	lbu	a4,0(a1)
  e4:	00f71763          	bne	a4,a5,f2 <strcmp+0x20>
    p++, q++;
  e8:	0505                	addi	a0,a0,1
  ea:	0585                	addi	a1,a1,1
  while(*p && *p == *q)
  ec:	00054783          	lbu	a5,0(a0)
  f0:	fbe5                	bnez	a5,e0 <strcmp+0xe>
  return (uchar)*p - (uchar)*q;
  f2:	0005c503          	lbu	a0,0(a1)
}
  f6:	40a7853b          	subw	a0,a5,a0
  fa:	60a2                	ld	ra,8(sp)
  fc:	6402                	ld	s0,0(sp)
  fe:	0141                	addi	sp,sp,16
 100:	8082                	ret

0000000000000102 <strlen>:

uint
strlen(const char *s)
{
 102:	1141                	addi	sp,sp,-16
 104:	e406                	sd	ra,8(sp)
 106:	e022                	sd	s0,0(sp)
 108:	0800                	addi	s0,sp,16
  int n;

  for(n = 0; s[n]; n++)
 10a:	00054783          	lbu	a5,0(a0)
 10e:	cf91                	beqz	a5,12a <strlen+0x28>
 110:	00150793          	addi	a5,a0,1
 114:	86be                	mv	a3,a5
 116:	0785                	addi	a5,a5,1
 118:	fff7c703          	lbu	a4,-1(a5)
 11c:	ff65                	bnez	a4,114 <strlen+0x12>
 11e:	40a6853b          	subw	a0,a3,a0
    ;
  return n;
}
 122:	60a2                	ld	ra,8(sp)
 124:	6402                	ld	s0,0(sp)
 126:	0141                	addi	sp,sp,16
 128:	8082                	ret
  for(n = 0; s[n]; n++)
 12a:	4501                	li	a0,0
 12c:	bfdd                	j	122 <strlen+0x20>

000000000000012e <memset>:

void*
memset(void *dst, int c, uint n)
{
 12e:	1141                	addi	sp,sp,-16
 130:	e406                	sd	ra,8(sp)
 132:	e022                	sd	s0,0(sp)
 134:	0800                	addi	s0,sp,16
  char *cdst = (char *) dst;
  int i;
  for(i = 0; i < n; i++){
 136:	ca19                	beqz	a2,14c <memset+0x1e>
 138:	87aa                	mv	a5,a0
 13a:	1602                	slli	a2,a2,0x20
 13c:	9201                	srli	a2,a2,0x20
 13e:	00a60733          	add	a4,a2,a0
    cdst[i] = c;
 142:	00b78023          	sb	a1,0(a5)
  for(i = 0; i < n; i++){
 146:	0785                	addi	a5,a5,1
 148:	fee79de3          	bne	a5,a4,142 <memset+0x14>
  }
  return dst;
}
 14c:	60a2                	ld	ra,8(sp)
 14e:	6402                	ld	s0,0(sp)
 150:	0141                	addi	sp,sp,16
 152:	8082                	ret

0000000000000154 <strchr>:

char*
strchr(const char *s, char c)
{
 154:	1141                	addi	sp,sp,-16
 156:	e406                	sd	ra,8(sp)
 158:	e022                	sd	s0,0(sp)
 15a:	0800                	addi	s0,sp,16
  for(; *s; s++)
 15c:	00054783          	lbu	a5,0(a0)
 160:	cf81                	beqz	a5,178 <strchr+0x24>
    if(*s == c)
 162:	00f58763          	beq	a1,a5,170 <strchr+0x1c>
  for(; *s; s++)
 166:	0505                	addi	a0,a0,1
 168:	00054783          	lbu	a5,0(a0)
 16c:	fbfd                	bnez	a5,162 <strchr+0xe>
      return (char*)s;
  return 0;
 16e:	4501                	li	a0,0
}
 170:	60a2                	ld	ra,8(sp)
 172:	6402                	ld	s0,0(sp)
 174:	0141                	addi	sp,sp,16
 176:	8082                	ret
  return 0;
 178:	4501                	li	a0,0
 17a:	bfdd                	j	170 <strchr+0x1c>

000000000000017c <gets>:

char*
gets(char *buf, int max)
{
 17c:	711d                	addi	sp,sp,-96
 17e:	ec86                	sd	ra,88(sp)
 180:	e8a2                	sd	s0,80(sp)
 182:	e4a6                	sd	s1,72(sp)
 184:	e0ca                	sd	s2,64(sp)
 186:	fc4e                	sd	s3,56(sp)
 188:	f852                	sd	s4,48(sp)
 18a:	f456                	sd	s5,40(sp)
 18c:	f05a                	sd	s6,32(sp)
 18e:	ec5e                	sd	s7,24(sp)
 190:	e862                	sd	s8,16(sp)
 192:	1080                	addi	s0,sp,96
 194:	8baa                	mv	s7,a0
 196:	8a2e                	mv	s4,a1
  int i, cc;
  char c;

  for(i=0; i+1 < max; ){
 198:	892a                	mv	s2,a0
 19a:	4481                	li	s1,0
    cc = read(0, &c, 1);
 19c:	faf40b13          	addi	s6,s0,-81
 1a0:	4a85                	li	s5,1
  for(i=0; i+1 < max; ){
 1a2:	8c26                	mv	s8,s1
 1a4:	0014899b          	addiw	s3,s1,1
 1a8:	84ce                	mv	s1,s3
 1aa:	0349d463          	bge	s3,s4,1d2 <gets+0x56>
    cc = read(0, &c, 1);
 1ae:	8656                	mv	a2,s5
 1b0:	85da                	mv	a1,s6
 1b2:	4501                	li	a0,0
 1b4:	1bc000ef          	jal	370 <read>
    if(cc < 1)
 1b8:	00a05d63          	blez	a0,1d2 <gets+0x56>
      break;
    buf[i++] = c;
 1bc:	faf44783          	lbu	a5,-81(s0)
 1c0:	00f90023          	sb	a5,0(s2)
    if(c == '\n' || c == '\r')
 1c4:	0905                	addi	s2,s2,1
 1c6:	ff678713          	addi	a4,a5,-10
 1ca:	c319                	beqz	a4,1d0 <gets+0x54>
 1cc:	17cd                	addi	a5,a5,-13
 1ce:	fbf1                	bnez	a5,1a2 <gets+0x26>
    buf[i++] = c;
 1d0:	8c4e                	mv	s8,s3
      break;
  }
  buf[i] = '\0';
 1d2:	9c5e                	add	s8,s8,s7
 1d4:	000c0023          	sb	zero,0(s8)
  return buf;
}
 1d8:	855e                	mv	a0,s7
 1da:	60e6                	ld	ra,88(sp)
 1dc:	6446                	ld	s0,80(sp)
 1de:	64a6                	ld	s1,72(sp)
 1e0:	6906                	ld	s2,64(sp)
 1e2:	79e2                	ld	s3,56(sp)
 1e4:	7a42                	ld	s4,48(sp)
 1e6:	7aa2                	ld	s5,40(sp)
 1e8:	7b02                	ld	s6,32(sp)
 1ea:	6be2                	ld	s7,24(sp)
 1ec:	6c42                	ld	s8,16(sp)
 1ee:	6125                	addi	sp,sp,96
 1f0:	8082                	ret

00000000000001f2 <stat>:

int
stat(const char *n, struct stat *st)
{
 1f2:	1101                	addi	sp,sp,-32
 1f4:	ec06                	sd	ra,24(sp)
 1f6:	e822                	sd	s0,16(sp)
 1f8:	e04a                	sd	s2,0(sp)
 1fa:	1000                	addi	s0,sp,32
 1fc:	892e                	mv	s2,a1
  int fd;
  int r;

  fd = open(n, O_RDONLY);
 1fe:	4581                	li	a1,0
 200:	198000ef          	jal	398 <open>
  if(fd < 0)
 204:	02054263          	bltz	a0,228 <stat+0x36>
 208:	e426                	sd	s1,8(sp)
 20a:	84aa                	mv	s1,a0
    return -1;
  r = fstat(fd, st);
 20c:	85ca                	mv	a1,s2
 20e:	1a2000ef          	jal	3b0 <fstat>
 212:	892a                	mv	s2,a0
  close(fd);
 214:	8526                	mv	a0,s1
 216:	16a000ef          	jal	380 <close>
  return r;
 21a:	64a2                	ld	s1,8(sp)
}
 21c:	854a                	mv	a0,s2
 21e:	60e2                	ld	ra,24(sp)
 220:	6442                	ld	s0,16(sp)
 222:	6902                	ld	s2,0(sp)
 224:	6105                	addi	sp,sp,32
 226:	8082                	ret
    return -1;
 228:	57fd                	li	a5,-1
 22a:	893e                	mv	s2,a5
 22c:	bfc5                	j	21c <stat+0x2a>

000000000000022e <atoi>:

int
atoi(const char *s)
{
 22e:	1141                	addi	sp,sp,-16
 230:	e406                	sd	ra,8(sp)
 232:	e022                	sd	s0,0(sp)
 234:	0800                	addi	s0,sp,16
  int n;

  n = 0;
  while('0' <= *s && *s <= '9')
 236:	00054683          	lbu	a3,0(a0)
 23a:	fd06879b          	addiw	a5,a3,-48
 23e:	0ff7f793          	zext.b	a5,a5
 242:	4625                	li	a2,9
 244:	02f66963          	bltu	a2,a5,276 <atoi+0x48>
 248:	872a                	mv	a4,a0
  n = 0;
 24a:	4501                	li	a0,0
    n = n*10 + *s++ - '0';
 24c:	0705                	addi	a4,a4,1
 24e:	0025179b          	slliw	a5,a0,0x2
 252:	9fa9                	addw	a5,a5,a0
 254:	0017979b          	slliw	a5,a5,0x1
 258:	9fb5                	addw	a5,a5,a3
 25a:	fd07851b          	addiw	a0,a5,-48
  while('0' <= *s && *s <= '9')
 25e:	00074683          	lbu	a3,0(a4)
 262:	fd06879b          	addiw	a5,a3,-48
 266:	0ff7f793          	zext.b	a5,a5
 26a:	fef671e3          	bgeu	a2,a5,24c <atoi+0x1e>
  return n;
}
 26e:	60a2                	ld	ra,8(sp)
 270:	6402                	ld	s0,0(sp)
 272:	0141                	addi	sp,sp,16
 274:	8082                	ret
  n = 0;
 276:	4501                	li	a0,0
 278:	bfdd                	j	26e <atoi+0x40>

000000000000027a <memmove>:

void*
memmove(void *vdst, const void *vsrc, int n)
{
 27a:	1141                	addi	sp,sp,-16
 27c:	e406                	sd	ra,8(sp)
 27e:	e022                	sd	s0,0(sp)
 280:	0800                	addi	s0,sp,16
  char *dst;
  const char *src;

  dst = vdst;
  src = vsrc;
  if (src > dst) {
 282:	02b57563          	bgeu	a0,a1,2ac <memmove+0x32>
    while(n-- > 0)
 286:	00c05f63          	blez	a2,2a4 <memmove+0x2a>
 28a:	1602                	slli	a2,a2,0x20
 28c:	9201                	srli	a2,a2,0x20
 28e:	00c507b3          	add	a5,a0,a2
  dst = vdst;
 292:	872a                	mv	a4,a0
      *dst++ = *src++;
 294:	0585                	addi	a1,a1,1
 296:	0705                	addi	a4,a4,1
 298:	fff5c683          	lbu	a3,-1(a1)
 29c:	fed70fa3          	sb	a3,-1(a4)
    while(n-- > 0)
 2a0:	fee79ae3          	bne	a5,a4,294 <memmove+0x1a>
    src += n;
    while(n-- > 0)
      *--dst = *--src;
  }
  return vdst;
}
 2a4:	60a2                	ld	ra,8(sp)
 2a6:	6402                	ld	s0,0(sp)
 2a8:	0141                	addi	sp,sp,16
 2aa:	8082                	ret
    while(n-- > 0)
 2ac:	fec05ce3          	blez	a2,2a4 <memmove+0x2a>
    dst += n;
 2b0:	00c50733          	add	a4,a0,a2
    src += n;
 2b4:	95b2                	add	a1,a1,a2
 2b6:	fff6079b          	addiw	a5,a2,-1
 2ba:	1782                	slli	a5,a5,0x20
 2bc:	9381                	srli	a5,a5,0x20
 2be:	fff7c793          	not	a5,a5
 2c2:	97ba                	add	a5,a5,a4
      *--dst = *--src;
 2c4:	15fd                	addi	a1,a1,-1
 2c6:	177d                	addi	a4,a4,-1
 2c8:	0005c683          	lbu	a3,0(a1)
 2cc:	00d70023          	sb	a3,0(a4)
    while(n-- > 0)
 2d0:	fef71ae3          	bne	a4,a5,2c4 <memmove+0x4a>
 2d4:	bfc1                	j	2a4 <memmove+0x2a>

00000000000002d6 <memcmp>:

int
memcmp(const void *s1, const void *s2, uint n)
{
 2d6:	1141                	addi	sp,sp,-16
 2d8:	e406                	sd	ra,8(sp)
 2da:	e022                	sd	s0,0(sp)
 2dc:	0800                	addi	s0,sp,16
  const char *p1 = s1, *p2 = s2;
  while (n-- > 0) {
 2de:	c61d                	beqz	a2,30c <memcmp+0x36>
 2e0:	1602                	slli	a2,a2,0x20
 2e2:	9201                	srli	a2,a2,0x20
 2e4:	00c506b3          	add	a3,a0,a2
    if (*p1 != *p2) {
 2e8:	00054783          	lbu	a5,0(a0)
 2ec:	0005c703          	lbu	a4,0(a1)
 2f0:	00e79863          	bne	a5,a4,300 <memcmp+0x2a>
      return *p1 - *p2;
    }
    p1++;
 2f4:	0505                	addi	a0,a0,1
    p2++;
 2f6:	0585                	addi	a1,a1,1
  while (n-- > 0) {
 2f8:	fed518e3          	bne	a0,a3,2e8 <memcmp+0x12>
  }
  return 0;
 2fc:	4501                	li	a0,0
 2fe:	a019                	j	304 <memcmp+0x2e>
      return *p1 - *p2;
 300:	40e7853b          	subw	a0,a5,a4
}
 304:	60a2                	ld	ra,8(sp)
 306:	6402                	ld	s0,0(sp)
 308:	0141                	addi	sp,sp,16
 30a:	8082                	ret
  return 0;
 30c:	4501                	li	a0,0
 30e:	bfdd                	j	304 <memcmp+0x2e>

0000000000000310 <memcpy>:

void *
memcpy(void *dst, const void *src, uint n)
{
 310:	1141                	addi	sp,sp,-16
 312:	e406                	sd	ra,8(sp)
 314:	e022                	sd	s0,0(sp)
 316:	0800                	addi	s0,sp,16
  return memmove(dst, src, n);
 318:	f63ff0ef          	jal	27a <memmove>
}
 31c:	60a2                	ld	ra,8(sp)
 31e:	6402                	ld	s0,0(sp)
 320:	0141                	addi	sp,sp,16
 322:	8082                	ret

0000000000000324 <sbrk>:

char *
sbrk(int n) {
 324:	1141                	addi	sp,sp,-16
 326:	e406                	sd	ra,8(sp)
 328:	e022                	sd	s0,0(sp)
 32a:	0800                	addi	s0,sp,16
  return sys_sbrk(n, SBRK_EAGER);
 32c:	4585                	li	a1,1
 32e:	0b2000ef          	jal	3e0 <sys_sbrk>
}
 332:	60a2                	ld	ra,8(sp)
 334:	6402                	ld	s0,0(sp)
 336:	0141                	addi	sp,sp,16
 338:	8082                	ret

000000000000033a <sbrklazy>:

char *
sbrklazy(int n) {
 33a:	1141                	addi	sp,sp,-16
 33c:	e406                	sd	ra,8(sp)
 33e:	e022                	sd	s0,0(sp)
 340:	0800                	addi	s0,sp,16
  return sys_sbrk(n, SBRK_LAZY);
 342:	4589                	li	a1,2
 344:	09c000ef          	jal	3e0 <sys_sbrk>
}
 348:	60a2                	ld	ra,8(sp)
 34a:	6402                	ld	s0,0(sp)
 34c:	0141                	addi	sp,sp,16
 34e:	8082                	ret

0000000000000350 <fork>:
# generated by usys.pl - do not edit
#include "kernel/syscall.h"
.global fork
fork:
 li a7, SYS_fork
 350:	4885                	li	a7,1
 ecall
 352:	00000073          	ecall
 ret
 356:	8082                	ret

0000000000000358 <exit>:
.global exit
exit:
 li a7, SYS_exit
 358:	4889                	li	a7,2
 ecall
 35a:	00000073          	ecall
 ret
 35e:	8082                	ret

0000000000000360 <wait>:
.global wait
wait:
 li a7, SYS_wait
 360:	488d                	li	a7,3
 ecall
 362:	00000073          	ecall
 ret
 366:	8082                	ret

0000000000000368 <pipe>:
.global pipe
pipe:
 li a7, SYS_pipe
 368:	4891                	li	a7,4
 ecall
 36a:	00000073          	ecall
 ret
 36e:	8082                	ret

0000000000000370 <read>:
.global read
read:
 li a7, SYS_read
 370:	4895                	li	a7,5
 ecall
 372:	00000073          	ecall
 ret
 376:	8082                	ret

0000000000000378 <write>:
.global write
write:
 li a7, SYS_write
 378:	48c1                	li	a7,16
 ecall
 37a:	00000073          	ecall
 ret
 37e:	8082                	ret

0000000000000380 <close>:
.global close
close:
 li a7, SYS_close
 380:	48d5                	li	a7,21
 ecall
 382:	00000073          	ecall
 ret
 386:	8082                	ret

0000000000000388 <kill>:
.global kill
kill:
 li a7, SYS_kill
 388:	4899                	li	a7,6
 ecall
 38a:	00000073          	ecall
 ret
 38e:	8082                	ret

0000000000000390 <exec>:
.global exec
exec:
 li a7, SYS_exec
 390:	489d                	li	a7,7
 ecall
 392:	00000073          	ecall
 ret
 396:	8082                	ret

0000000000000398 <open>:
.global open
open:
 li a7, SYS_open
 398:	48bd                	li	a7,15
 ecall
 39a:	00000073          	ecall
 ret
 39e:	8082                	ret

00000000000003a0 <mknod>:
.global mknod
mknod:
 li a7, SYS_mknod
 3a0:	48c5                	li	a7,17
 ecall
 3a2:	00000073          	ecall
 ret
 3a6:	8082                	ret

00000000000003a8 <unlink>:
.global unlink
unlink:
 li a7, SYS_unlink
 3a8:	48c9                	li	a7,18
 ecall
 3aa:	00000073          	ecall
 ret
 3ae:	8082                	ret

00000000000003b0 <fstat>:
.global fstat
fstat:
 li a7, SYS_fstat
 3b0:	48a1                	li	a7,8
 ecall
 3b2:	00000073          	ecall
 ret
 3b6:	8082                	ret

00000000000003b8 <link>:
.global link
link:
 li a7, SYS_link
 3b8:	48cd                	li	a7,19
 ecall
 3ba:	00000073          	ecall
 ret
 3be:	8082                	ret

00000000000003c0 <mkdir>:
.global mkdir
mkdir:
 li a7, SYS_mkdir
 3c0:	48d1                	li	a7,20
 ecall
 3c2:	00000073          	ecall
 ret
 3c6:	8082                	ret

00000000000003c8 <chdir>:
.global chdir
chdir:
 li a7, SYS_chdir
 3c8:	48a5                	li	a7,9
 ecall
 3ca:	00000073          	ecall
 ret
 3ce:	8082                	ret

00000000000003d0 <dup>:
.global dup
dup:
 li a7, SYS_dup
 3d0:	48a9                	li	a7,10
 ecall
 3d2:	00000073          	ecall
 ret
 3d6:	8082                	ret

00000000000003d8 <getpid>:
.global getpid
getpid:
 li a7, SYS_getpid
 3d8:	48ad                	li	a7,11
 ecall
 3da:	00000073          	ecall
 ret
 3de:	8082                	ret

00000000000003e0 <sys_sbrk>:
.global sys_sbrk
sys_sbrk:
 li a7, SYS_sbrk
 3e0:	48b1                	li	a7,12
 ecall
 3e2:	00000073          	ecall
 ret
 3e6:	8082                	ret

00000000000003e8 <pause>:
.global pause
pause:
 li a7, SYS_pause
 3e8:	48b5                	li	a7,13
 ecall
 3ea:	00000073          	ecall
 ret
 3ee:	8082                	ret

00000000000003f0 <uptime>:
.global uptime
uptime:
 li a7, SYS_uptime
 3f0:	48b9                	li	a7,14
 ecall
 3f2:	00000073          	ecall
 ret
 3f6:	8082                	ret

00000000000003f8 <putc>:

static char digits[] = "0123456789ABCDEF";

static void
putc(int fd, char c)
{
 3f8:	1101                	addi	sp,sp,-32
 3fa:	ec06                	sd	ra,24(sp)
 3fc:	e822                	sd	s0,16(sp)
 3fe:	1000                	addi	s0,sp,32
 400:	feb407a3          	sb	a1,-17(s0)
  write(fd, &c, 1);
 404:	4605                	li	a2,1
 406:	fef40593          	addi	a1,s0,-17
 40a:	f6fff0ef          	jal	378 <write>
}
 40e:	60e2                	ld	ra,24(sp)
 410:	6442                	ld	s0,16(sp)
 412:	6105                	addi	sp,sp,32
 414:	8082                	ret

0000000000000416 <printint>:

static void
printint(int fd, long long xx, int base, int sgn)
{
 416:	715d                	addi	sp,sp,-80
 418:	e486                	sd	ra,72(sp)
 41a:	e0a2                	sd	s0,64(sp)
 41c:	f84a                	sd	s2,48(sp)
 41e:	f44e                	sd	s3,40(sp)
 420:	0880                	addi	s0,sp,80
 422:	892a                	mv	s2,a0
  char buf[20];
  int i, neg;
  unsigned long long x;

  neg = 0;
  if(sgn && xx < 0){
 424:	c6d1                	beqz	a3,4b0 <printint+0x9a>
 426:	0805d563          	bgez	a1,4b0 <printint+0x9a>
    neg = 1;
    x = -xx;
 42a:	40b005b3          	neg	a1,a1
    neg = 1;
 42e:	4305                	li	t1,1
  } else {
    x = xx;
  }

  i = 0;
 430:	fb840993          	addi	s3,s0,-72
  neg = 0;
 434:	86ce                	mv	a3,s3
  i = 0;
 436:	4701                	li	a4,0
  do{
    buf[i++] = digits[x % base];
 438:	00000817          	auipc	a6,0x0
 43c:	5f080813          	addi	a6,a6,1520 # a28 <digits>
 440:	88ba                	mv	a7,a4
 442:	0017051b          	addiw	a0,a4,1
 446:	872a                	mv	a4,a0
 448:	02c5f7b3          	remu	a5,a1,a2
 44c:	97c2                	add	a5,a5,a6
 44e:	0007c783          	lbu	a5,0(a5)
 452:	00f68023          	sb	a5,0(a3)
  }while((x /= base) != 0);
 456:	87ae                	mv	a5,a1
 458:	02c5d5b3          	divu	a1,a1,a2
 45c:	0685                	addi	a3,a3,1
 45e:	fec7f1e3          	bgeu	a5,a2,440 <printint+0x2a>
  if(neg)
 462:	00030c63          	beqz	t1,47a <printint+0x64>
    buf[i++] = '-';
 466:	fd050793          	addi	a5,a0,-48
 46a:	00878533          	add	a0,a5,s0
 46e:	02d00793          	li	a5,45
 472:	fef50423          	sb	a5,-24(a0)
 476:	0028871b          	addiw	a4,a7,2

  while(--i >= 0)
 47a:	02e05563          	blez	a4,4a4 <printint+0x8e>
 47e:	fc26                	sd	s1,56(sp)
 480:	377d                	addiw	a4,a4,-1
 482:	00e984b3          	add	s1,s3,a4
 486:	19fd                	addi	s3,s3,-1
 488:	99ba                	add	s3,s3,a4
 48a:	1702                	slli	a4,a4,0x20
 48c:	9301                	srli	a4,a4,0x20
 48e:	40e989b3          	sub	s3,s3,a4
    putc(fd, buf[i]);
 492:	0004c583          	lbu	a1,0(s1)
 496:	854a                	mv	a0,s2
 498:	f61ff0ef          	jal	3f8 <putc>
  while(--i >= 0)
 49c:	14fd                	addi	s1,s1,-1
 49e:	ff349ae3          	bne	s1,s3,492 <printint+0x7c>
 4a2:	74e2                	ld	s1,56(sp)
}
 4a4:	60a6                	ld	ra,72(sp)
 4a6:	6406                	ld	s0,64(sp)
 4a8:	7942                	ld	s2,48(sp)
 4aa:	79a2                	ld	s3,40(sp)
 4ac:	6161                	addi	sp,sp,80
 4ae:	8082                	ret
  neg = 0;
 4b0:	4301                	li	t1,0
 4b2:	bfbd                	j	430 <printint+0x1a>

00000000000004b4 <vprintf>:
}

// Print to the given fd. Only understands %d, %x, %p, %c, %s.
void
vprintf(int fd, const char *fmt, va_list ap)
{
 4b4:	711d                	addi	sp,sp,-96
 4b6:	ec86                	sd	ra,88(sp)
 4b8:	e8a2                	sd	s0,80(sp)
 4ba:	e4a6                	sd	s1,72(sp)
 4bc:	1080                	addi	s0,sp,96
  char *s;
  int c0, c1, c2, i, state;

  state = 0;
  for(i = 0; fmt[i]; i++){
 4be:	0005c483          	lbu	s1,0(a1)
 4c2:	22048363          	beqz	s1,6e8 <vprintf+0x234>
 4c6:	e0ca                	sd	s2,64(sp)
 4c8:	fc4e                	sd	s3,56(sp)
 4ca:	f852                	sd	s4,48(sp)
 4cc:	f456                	sd	s5,40(sp)
 4ce:	f05a                	sd	s6,32(sp)
 4d0:	ec5e                	sd	s7,24(sp)
 4d2:	e862                	sd	s8,16(sp)
 4d4:	8b2a                	mv	s6,a0
 4d6:	8a2e                	mv	s4,a1
 4d8:	8bb2                	mv	s7,a2
  state = 0;
 4da:	4981                	li	s3,0
  for(i = 0; fmt[i]; i++){
 4dc:	4901                	li	s2,0
 4de:	4701                	li	a4,0
      if(c0 == '%'){
        state = '%';
      } else {
        putc(fd, c0);
      }
    } else if(state == '%'){
 4e0:	02500a93          	li	s5,37
      c1 = c2 = 0;
      if(c0) c1 = fmt[i+1] & 0xff;
      if(c1) c2 = fmt[i+2] & 0xff;
      if(c0 == 'd'){
 4e4:	06400c13          	li	s8,100
 4e8:	a00d                	j	50a <vprintf+0x56>
        putc(fd, c0);
 4ea:	85a6                	mv	a1,s1
 4ec:	855a                	mv	a0,s6
 4ee:	f0bff0ef          	jal	3f8 <putc>
 4f2:	a019                	j	4f8 <vprintf+0x44>
    } else if(state == '%'){
 4f4:	03598363          	beq	s3,s5,51a <vprintf+0x66>
  for(i = 0; fmt[i]; i++){
 4f8:	0019079b          	addiw	a5,s2,1
 4fc:	893e                	mv	s2,a5
 4fe:	873e                	mv	a4,a5
 500:	97d2                	add	a5,a5,s4
 502:	0007c483          	lbu	s1,0(a5)
 506:	1c048a63          	beqz	s1,6da <vprintf+0x226>
    c0 = fmt[i] & 0xff;
 50a:	0004879b          	sext.w	a5,s1
    if(state == 0){
 50e:	fe0993e3          	bnez	s3,4f4 <vprintf+0x40>
      if(c0 == '%'){
 512:	fd579ce3          	bne	a5,s5,4ea <vprintf+0x36>
        state = '%';
 516:	89be                	mv	s3,a5
 518:	b7c5                	j	4f8 <vprintf+0x44>
      if(c0) c1 = fmt[i+1] & 0xff;
 51a:	00ea06b3          	add	a3,s4,a4
 51e:	0016c603          	lbu	a2,1(a3)
      if(c1) c2 = fmt[i+2] & 0xff;
 522:	1c060863          	beqz	a2,6f2 <vprintf+0x23e>
      if(c0 == 'd'){
 526:	03878763          	beq	a5,s8,554 <vprintf+0xa0>
        printint(fd, va_arg(ap, int), 10, 1);
      } else if(c0 == 'l' && c1 == 'd'){
 52a:	f9478693          	addi	a3,a5,-108
 52e:	0016b693          	seqz	a3,a3
 532:	f9c60593          	addi	a1,a2,-100
 536:	e99d                	bnez	a1,56c <vprintf+0xb8>
 538:	ca95                	beqz	a3,56c <vprintf+0xb8>
        printint(fd, va_arg(ap, uint64), 10, 1);
 53a:	008b8493          	addi	s1,s7,8
 53e:	4685                	li	a3,1
 540:	4629                	li	a2,10
 542:	000bb583          	ld	a1,0(s7)
 546:	855a                	mv	a0,s6
 548:	ecfff0ef          	jal	416 <printint>
        i += 1;
 54c:	2905                	addiw	s2,s2,1
        printint(fd, va_arg(ap, uint64), 10, 1);
 54e:	8ba6                	mv	s7,s1
        // Unknown % sequence.  Print it to draw attention.
        putc(fd, '%');
        putc(fd, c0);
      }

      state = 0;
 550:	4981                	li	s3,0
 552:	b75d                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, int), 10, 1);
 554:	008b8493          	addi	s1,s7,8
 558:	4685                	li	a3,1
 55a:	4629                	li	a2,10
 55c:	000ba583          	lw	a1,0(s7)
 560:	855a                	mv	a0,s6
 562:	eb5ff0ef          	jal	416 <printint>
 566:	8ba6                	mv	s7,s1
      state = 0;
 568:	4981                	li	s3,0
 56a:	b779                	j	4f8 <vprintf+0x44>
      if(c1) c2 = fmt[i+2] & 0xff;
 56c:	9752                	add	a4,a4,s4
 56e:	00274583          	lbu	a1,2(a4)
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'd'){
 572:	f9460713          	addi	a4,a2,-108
 576:	00173713          	seqz	a4,a4
 57a:	8f75                	and	a4,a4,a3
 57c:	f9c58513          	addi	a0,a1,-100
 580:	18051363          	bnez	a0,706 <vprintf+0x252>
 584:	18070163          	beqz	a4,706 <vprintf+0x252>
        printint(fd, va_arg(ap, uint64), 10, 1);
 588:	008b8493          	addi	s1,s7,8
 58c:	4685                	li	a3,1
 58e:	4629                	li	a2,10
 590:	000bb583          	ld	a1,0(s7)
 594:	855a                	mv	a0,s6
 596:	e81ff0ef          	jal	416 <printint>
        i += 2;
 59a:	2909                	addiw	s2,s2,2
        printint(fd, va_arg(ap, uint64), 10, 1);
 59c:	8ba6                	mv	s7,s1
      state = 0;
 59e:	4981                	li	s3,0
        i += 2;
 5a0:	bfa1                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint32), 10, 0);
 5a2:	008b8493          	addi	s1,s7,8
 5a6:	4681                	li	a3,0
 5a8:	4629                	li	a2,10
 5aa:	000be583          	lwu	a1,0(s7)
 5ae:	855a                	mv	a0,s6
 5b0:	e67ff0ef          	jal	416 <printint>
 5b4:	8ba6                	mv	s7,s1
      state = 0;
 5b6:	4981                	li	s3,0
 5b8:	b781                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint64), 10, 0);
 5ba:	008b8493          	addi	s1,s7,8
 5be:	4681                	li	a3,0
 5c0:	4629                	li	a2,10
 5c2:	000bb583          	ld	a1,0(s7)
 5c6:	855a                	mv	a0,s6
 5c8:	e4fff0ef          	jal	416 <printint>
        i += 1;
 5cc:	2905                	addiw	s2,s2,1
        printint(fd, va_arg(ap, uint64), 10, 0);
 5ce:	8ba6                	mv	s7,s1
      state = 0;
 5d0:	4981                	li	s3,0
 5d2:	b71d                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint64), 10, 0);
 5d4:	008b8493          	addi	s1,s7,8
 5d8:	4681                	li	a3,0
 5da:	4629                	li	a2,10
 5dc:	000bb583          	ld	a1,0(s7)
 5e0:	855a                	mv	a0,s6
 5e2:	e35ff0ef          	jal	416 <printint>
        i += 2;
 5e6:	2909                	addiw	s2,s2,2
        printint(fd, va_arg(ap, uint64), 10, 0);
 5e8:	8ba6                	mv	s7,s1
      state = 0;
 5ea:	4981                	li	s3,0
        i += 2;
 5ec:	b731                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint32), 16, 0);
 5ee:	008b8493          	addi	s1,s7,8
 5f2:	4681                	li	a3,0
 5f4:	4641                	li	a2,16
 5f6:	000be583          	lwu	a1,0(s7)
 5fa:	855a                	mv	a0,s6
 5fc:	e1bff0ef          	jal	416 <printint>
 600:	8ba6                	mv	s7,s1
      state = 0;
 602:	4981                	li	s3,0
 604:	bdd5                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint64), 16, 0);
 606:	008b8493          	addi	s1,s7,8
 60a:	4681                	li	a3,0
 60c:	4641                	li	a2,16
 60e:	000bb583          	ld	a1,0(s7)
 612:	855a                	mv	a0,s6
 614:	e03ff0ef          	jal	416 <printint>
        i += 1;
 618:	2905                	addiw	s2,s2,1
        printint(fd, va_arg(ap, uint64), 16, 0);
 61a:	8ba6                	mv	s7,s1
      state = 0;
 61c:	4981                	li	s3,0
 61e:	bde9                	j	4f8 <vprintf+0x44>
        printint(fd, va_arg(ap, uint64), 16, 0);
 620:	008b8493          	addi	s1,s7,8
 624:	4681                	li	a3,0
 626:	4641                	li	a2,16
 628:	000bb583          	ld	a1,0(s7)
 62c:	855a                	mv	a0,s6
 62e:	de9ff0ef          	jal	416 <printint>
        i += 2;
 632:	2909                	addiw	s2,s2,2
        printint(fd, va_arg(ap, uint64), 16, 0);
 634:	8ba6                	mv	s7,s1
      state = 0;
 636:	4981                	li	s3,0
        i += 2;
 638:	b5c1                	j	4f8 <vprintf+0x44>
 63a:	e466                	sd	s9,8(sp)
        printptr(fd, va_arg(ap, uint64));
 63c:	008b8793          	addi	a5,s7,8
 640:	8cbe                	mv	s9,a5
 642:	000bb983          	ld	s3,0(s7)
  putc(fd, '0');
 646:	03000593          	li	a1,48
 64a:	855a                	mv	a0,s6
 64c:	dadff0ef          	jal	3f8 <putc>
  putc(fd, 'x');
 650:	07800593          	li	a1,120
 654:	855a                	mv	a0,s6
 656:	da3ff0ef          	jal	3f8 <putc>
 65a:	44c1                	li	s1,16
    putc(fd, digits[x >> (sizeof(uint64) * 8 - 4)]);
 65c:	00000b97          	auipc	s7,0x0
 660:	3ccb8b93          	addi	s7,s7,972 # a28 <digits>
 664:	03c9d793          	srli	a5,s3,0x3c
 668:	97de                	add	a5,a5,s7
 66a:	0007c583          	lbu	a1,0(a5)
 66e:	855a                	mv	a0,s6
 670:	d89ff0ef          	jal	3f8 <putc>
  for (i = 0; i < (sizeof(uint64) * 2); i++, x <<= 4)
 674:	0992                	slli	s3,s3,0x4
 676:	34fd                	addiw	s1,s1,-1
 678:	f4f5                	bnez	s1,664 <vprintf+0x1b0>
        printptr(fd, va_arg(ap, uint64));
 67a:	8be6                	mv	s7,s9
      state = 0;
 67c:	4981                	li	s3,0
 67e:	6ca2                	ld	s9,8(sp)
 680:	bda5                	j	4f8 <vprintf+0x44>
        putc(fd, va_arg(ap, uint32));
 682:	008b8493          	addi	s1,s7,8
 686:	000bc583          	lbu	a1,0(s7)
 68a:	855a                	mv	a0,s6
 68c:	d6dff0ef          	jal	3f8 <putc>
 690:	8ba6                	mv	s7,s1
      state = 0;
 692:	4981                	li	s3,0
 694:	b595                	j	4f8 <vprintf+0x44>
        if((s = va_arg(ap, char*)) == 0)
 696:	008b8993          	addi	s3,s7,8
 69a:	000bb483          	ld	s1,0(s7)
 69e:	cc91                	beqz	s1,6ba <vprintf+0x206>
        for(; *s; s++)
 6a0:	0004c583          	lbu	a1,0(s1)
 6a4:	c985                	beqz	a1,6d4 <vprintf+0x220>
          putc(fd, *s);
 6a6:	855a                	mv	a0,s6
 6a8:	d51ff0ef          	jal	3f8 <putc>
        for(; *s; s++)
 6ac:	0485                	addi	s1,s1,1
 6ae:	0004c583          	lbu	a1,0(s1)
 6b2:	f9f5                	bnez	a1,6a6 <vprintf+0x1f2>
        if((s = va_arg(ap, char*)) == 0)
 6b4:	8bce                	mv	s7,s3
      state = 0;
 6b6:	4981                	li	s3,0
 6b8:	b581                	j	4f8 <vprintf+0x44>
          s = "(null)";
 6ba:	00000497          	auipc	s1,0x0
 6be:	36648493          	addi	s1,s1,870 # a20 <malloc+0x1ca>
        for(; *s; s++)
 6c2:	02800593          	li	a1,40
 6c6:	b7c5                	j	6a6 <vprintf+0x1f2>
        putc(fd, '%');
 6c8:	85be                	mv	a1,a5
 6ca:	855a                	mv	a0,s6
 6cc:	d2dff0ef          	jal	3f8 <putc>
      state = 0;
 6d0:	4981                	li	s3,0
 6d2:	b51d                	j	4f8 <vprintf+0x44>
        if((s = va_arg(ap, char*)) == 0)
 6d4:	8bce                	mv	s7,s3
      state = 0;
 6d6:	4981                	li	s3,0
 6d8:	b505                	j	4f8 <vprintf+0x44>
 6da:	6906                	ld	s2,64(sp)
 6dc:	79e2                	ld	s3,56(sp)
 6de:	7a42                	ld	s4,48(sp)
 6e0:	7aa2                	ld	s5,40(sp)
 6e2:	7b02                	ld	s6,32(sp)
 6e4:	6be2                	ld	s7,24(sp)
 6e6:	6c42                	ld	s8,16(sp)
    }
  }
}
 6e8:	60e6                	ld	ra,88(sp)
 6ea:	6446                	ld	s0,80(sp)
 6ec:	64a6                	ld	s1,72(sp)
 6ee:	6125                	addi	sp,sp,96
 6f0:	8082                	ret
      if(c0 == 'd'){
 6f2:	06400713          	li	a4,100
 6f6:	e4e78fe3          	beq	a5,a4,554 <vprintf+0xa0>
      } else if(c0 == 'l' && c1 == 'd'){
 6fa:	f9478693          	addi	a3,a5,-108
 6fe:	0016b693          	seqz	a3,a3
      c1 = c2 = 0;
 702:	85b2                	mv	a1,a2
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'd'){
 704:	4701                	li	a4,0
      } else if(c0 == 'u'){
 706:	07500513          	li	a0,117
 70a:	e8a78ce3          	beq	a5,a0,5a2 <vprintf+0xee>
      } else if(c0 == 'l' && c1 == 'u'){
 70e:	f8b60513          	addi	a0,a2,-117
 712:	e119                	bnez	a0,718 <vprintf+0x264>
 714:	ea0693e3          	bnez	a3,5ba <vprintf+0x106>
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'u'){
 718:	f8b58513          	addi	a0,a1,-117
 71c:	e119                	bnez	a0,722 <vprintf+0x26e>
 71e:	ea071be3          	bnez	a4,5d4 <vprintf+0x120>
      } else if(c0 == 'x'){
 722:	07800513          	li	a0,120
 726:	eca784e3          	beq	a5,a0,5ee <vprintf+0x13a>
      } else if(c0 == 'l' && c1 == 'x'){
 72a:	f8860613          	addi	a2,a2,-120
 72e:	e219                	bnez	a2,734 <vprintf+0x280>
 730:	ec069be3          	bnez	a3,606 <vprintf+0x152>
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'x'){
 734:	f8858593          	addi	a1,a1,-120
 738:	e199                	bnez	a1,73e <vprintf+0x28a>
 73a:	ee0713e3          	bnez	a4,620 <vprintf+0x16c>
      } else if(c0 == 'p'){
 73e:	07000713          	li	a4,112
 742:	eee78ce3          	beq	a5,a4,63a <vprintf+0x186>
      } else if(c0 == 'c'){
 746:	06300713          	li	a4,99
 74a:	f2e78ce3          	beq	a5,a4,682 <vprintf+0x1ce>
      } else if(c0 == 's'){
 74e:	07300713          	li	a4,115
 752:	f4e782e3          	beq	a5,a4,696 <vprintf+0x1e2>
      } else if(c0 == '%'){
 756:	02500713          	li	a4,37
 75a:	f6e787e3          	beq	a5,a4,6c8 <vprintf+0x214>
        putc(fd, '%');
 75e:	02500593          	li	a1,37
 762:	855a                	mv	a0,s6
 764:	c95ff0ef          	jal	3f8 <putc>
        putc(fd, c0);
 768:	85a6                	mv	a1,s1
 76a:	855a                	mv	a0,s6
 76c:	c8dff0ef          	jal	3f8 <putc>
      state = 0;
 770:	4981                	li	s3,0
 772:	b359                	j	4f8 <vprintf+0x44>

0000000000000774 <fprintf>:

void
fprintf(int fd, const char *fmt, ...)
{
 774:	715d                	addi	sp,sp,-80
 776:	ec06                	sd	ra,24(sp)
 778:	e822                	sd	s0,16(sp)
 77a:	1000                	addi	s0,sp,32
 77c:	e010                	sd	a2,0(s0)
 77e:	e414                	sd	a3,8(s0)
 780:	e818                	sd	a4,16(s0)
 782:	ec1c                	sd	a5,24(s0)
 784:	03043023          	sd	a6,32(s0)
 788:	03143423          	sd	a7,40(s0)
  va_list ap;

  va_start(ap, fmt);
 78c:	8622                	mv	a2,s0
 78e:	fe843423          	sd	s0,-24(s0)
  vprintf(fd, fmt, ap);
 792:	d23ff0ef          	jal	4b4 <vprintf>
}
 796:	60e2                	ld	ra,24(sp)
 798:	6442                	ld	s0,16(sp)
 79a:	6161                	addi	sp,sp,80
 79c:	8082                	ret

000000000000079e <printf>:

void
printf(const char *fmt, ...)
{
 79e:	711d                	addi	sp,sp,-96
 7a0:	ec06                	sd	ra,24(sp)
 7a2:	e822                	sd	s0,16(sp)
 7a4:	1000                	addi	s0,sp,32
 7a6:	e40c                	sd	a1,8(s0)
 7a8:	e810                	sd	a2,16(s0)
 7aa:	ec14                	sd	a3,24(s0)
 7ac:	f018                	sd	a4,32(s0)
 7ae:	f41c                	sd	a5,40(s0)
 7b0:	03043823          	sd	a6,48(s0)
 7b4:	03143c23          	sd	a7,56(s0)
  va_list ap;

  va_start(ap, fmt);
 7b8:	00840613          	addi	a2,s0,8
 7bc:	fec43423          	sd	a2,-24(s0)
  vprintf(1, fmt, ap);
 7c0:	85aa                	mv	a1,a0
 7c2:	4505                	li	a0,1
 7c4:	cf1ff0ef          	jal	4b4 <vprintf>
}
 7c8:	60e2                	ld	ra,24(sp)
 7ca:	6442                	ld	s0,16(sp)
 7cc:	6125                	addi	sp,sp,96
 7ce:	8082                	ret

00000000000007d0 <free>:
static Header base;
static Header *freep;

void
free(void *ap)
{
 7d0:	1141                	addi	sp,sp,-16
 7d2:	e406                	sd	ra,8(sp)
 7d4:	e022                	sd	s0,0(sp)
 7d6:	0800                	addi	s0,sp,16
  Header *bp, *p;

  bp = (Header*)ap - 1;
 7d8:	ff050693          	addi	a3,a0,-16
  for(p = freep; !(bp > p && bp < p->s.ptr); p = p->s.ptr)
 7dc:	00001797          	auipc	a5,0x1
 7e0:	8247b783          	ld	a5,-2012(a5) # 1000 <freep>
 7e4:	a039                	j	7f2 <free+0x22>
    if(p >= p->s.ptr && (bp > p || bp < p->s.ptr))
 7e6:	6398                	ld	a4,0(a5)
 7e8:	00e7e463          	bltu	a5,a4,7f0 <free+0x20>
 7ec:	00e6ea63          	bltu	a3,a4,800 <free+0x30>
{
 7f0:	87ba                	mv	a5,a4
  for(p = freep; !(bp > p && bp < p->s.ptr); p = p->s.ptr)
 7f2:	fed7fae3          	bgeu	a5,a3,7e6 <free+0x16>
 7f6:	6398                	ld	a4,0(a5)
 7f8:	00e6e463          	bltu	a3,a4,800 <free+0x30>
    if(p >= p->s.ptr && (bp > p || bp < p->s.ptr))
 7fc:	fee7eae3          	bltu	a5,a4,7f0 <free+0x20>
      break;
  if(bp + bp->s.size == p->s.ptr){
 800:	ff852583          	lw	a1,-8(a0)
 804:	6390                	ld	a2,0(a5)
 806:	02059813          	slli	a6,a1,0x20
 80a:	01c85713          	srli	a4,a6,0x1c
 80e:	9736                	add	a4,a4,a3
 810:	02e60563          	beq	a2,a4,83a <free+0x6a>
    bp->s.size += p->s.ptr->s.size;
    bp->s.ptr = p->s.ptr->s.ptr;
 814:	fec53823          	sd	a2,-16(a0)
  } else
    bp->s.ptr = p->s.ptr;
  if(p + p->s.size == bp){
 818:	4790                	lw	a2,8(a5)
 81a:	02061593          	slli	a1,a2,0x20
 81e:	01c5d713          	srli	a4,a1,0x1c
 822:	973e                	add	a4,a4,a5
 824:	02e68263          	beq	a3,a4,848 <free+0x78>
    p->s.size += bp->s.size;
    p->s.ptr = bp->s.ptr;
 828:	e394                	sd	a3,0(a5)
  } else
    p->s.ptr = bp;
  freep = p;
 82a:	00000717          	auipc	a4,0x0
 82e:	7cf73b23          	sd	a5,2006(a4) # 1000 <freep>
}
 832:	60a2                	ld	ra,8(sp)
 834:	6402                	ld	s0,0(sp)
 836:	0141                	addi	sp,sp,16
 838:	8082                	ret
    bp->s.size += p->s.ptr->s.size;
 83a:	4618                	lw	a4,8(a2)
 83c:	9f2d                	addw	a4,a4,a1
 83e:	fee52c23          	sw	a4,-8(a0)
    bp->s.ptr = p->s.ptr->s.ptr;
 842:	6398                	ld	a4,0(a5)
 844:	6310                	ld	a2,0(a4)
 846:	b7f9                	j	814 <free+0x44>
    p->s.size += bp->s.size;
 848:	ff852703          	lw	a4,-8(a0)
 84c:	9f31                	addw	a4,a4,a2
 84e:	c798                	sw	a4,8(a5)
    p->s.ptr = bp->s.ptr;
 850:	ff053683          	ld	a3,-16(a0)
 854:	bfd1                	j	828 <free+0x58>

0000000000000856 <malloc>:
  return freep;
}

void*
malloc(uint nbytes)
{
 856:	7139                	addi	sp,sp,-64
 858:	fc06                	sd	ra,56(sp)
 85a:	f822                	sd	s0,48(sp)
 85c:	f04a                	sd	s2,32(sp)
 85e:	ec4e                	sd	s3,24(sp)
 860:	0080                	addi	s0,sp,64
  Header *p, *prevp;
  uint nunits;

  nunits = (nbytes + sizeof(Header) - 1)/sizeof(Header) + 1;
 862:	02051993          	slli	s3,a0,0x20
 866:	0209d993          	srli	s3,s3,0x20
 86a:	09bd                	addi	s3,s3,15
 86c:	0049d993          	srli	s3,s3,0x4
 870:	2985                	addiw	s3,s3,1
 872:	894e                	mv	s2,s3
  if((prevp = freep) == 0){
 874:	00000517          	auipc	a0,0x0
 878:	78c53503          	ld	a0,1932(a0) # 1000 <freep>
 87c:	c905                	beqz	a0,8ac <malloc+0x56>
    base.s.ptr = freep = prevp = &base;
    base.s.size = 0;
  }
  for(p = prevp->s.ptr; ; prevp = p, p = p->s.ptr){
 87e:	611c                	ld	a5,0(a0)
    if(p->s.size >= nunits){
 880:	4798                	lw	a4,8(a5)
 882:	09377663          	bgeu	a4,s3,90e <malloc+0xb8>
 886:	f426                	sd	s1,40(sp)
 888:	e852                	sd	s4,16(sp)
 88a:	e456                	sd	s5,8(sp)
 88c:	e05a                	sd	s6,0(sp)
  if(nu < 4096)
 88e:	8a4e                	mv	s4,s3
 890:	6705                	lui	a4,0x1
 892:	00e9f363          	bgeu	s3,a4,898 <malloc+0x42>
 896:	6a05                	lui	s4,0x1
 898:	000a0b1b          	sext.w	s6,s4
  p = sbrk(nu * sizeof(Header));
 89c:	004a1a1b          	slliw	s4,s4,0x4
        p->s.size = nunits;
      }
      freep = prevp;
      return (void*)(p + 1);
    }
    if(p == freep)
 8a0:	00000497          	auipc	s1,0x0
 8a4:	76048493          	addi	s1,s1,1888 # 1000 <freep>
  if(p == SBRK_ERROR)
 8a8:	5afd                	li	s5,-1
 8aa:	a83d                	j	8e8 <malloc+0x92>
 8ac:	f426                	sd	s1,40(sp)
 8ae:	e852                	sd	s4,16(sp)
 8b0:	e456                	sd	s5,8(sp)
 8b2:	e05a                	sd	s6,0(sp)
    base.s.ptr = freep = prevp = &base;
 8b4:	00000797          	auipc	a5,0x0
 8b8:	75c78793          	addi	a5,a5,1884 # 1010 <base>
 8bc:	00000717          	auipc	a4,0x0
 8c0:	74f73223          	sd	a5,1860(a4) # 1000 <freep>
 8c4:	e39c                	sd	a5,0(a5)
    base.s.size = 0;
 8c6:	0007a423          	sw	zero,8(a5)
    if(p->s.size >= nunits){
 8ca:	b7d1                	j	88e <malloc+0x38>
        prevp->s.ptr = p->s.ptr;
 8cc:	6398                	ld	a4,0(a5)
 8ce:	e118                	sd	a4,0(a0)
 8d0:	a899                	j	926 <malloc+0xd0>
  hp->s.size = nu;
 8d2:	01652423          	sw	s6,8(a0)
  free((void*)(hp + 1));
 8d6:	0541                	addi	a0,a0,16
 8d8:	ef9ff0ef          	jal	7d0 <free>
  return freep;
 8dc:	6088                	ld	a0,0(s1)
      if((p = morecore(nunits)) == 0)
 8de:	c125                	beqz	a0,93e <malloc+0xe8>
  for(p = prevp->s.ptr; ; prevp = p, p = p->s.ptr){
 8e0:	611c                	ld	a5,0(a0)
    if(p->s.size >= nunits){
 8e2:	4798                	lw	a4,8(a5)
 8e4:	03277163          	bgeu	a4,s2,906 <malloc+0xb0>
    if(p == freep)
 8e8:	6098                	ld	a4,0(s1)
 8ea:	853e                	mv	a0,a5
 8ec:	fef71ae3          	bne	a4,a5,8e0 <malloc+0x8a>
  p = sbrk(nu * sizeof(Header));
 8f0:	8552                	mv	a0,s4
 8f2:	a33ff0ef          	jal	324 <sbrk>
  if(p == SBRK_ERROR)
 8f6:	fd551ee3          	bne	a0,s5,8d2 <malloc+0x7c>
        return 0;
 8fa:	4501                	li	a0,0
 8fc:	74a2                	ld	s1,40(sp)
 8fe:	6a42                	ld	s4,16(sp)
 900:	6aa2                	ld	s5,8(sp)
 902:	6b02                	ld	s6,0(sp)
 904:	a03d                	j	932 <malloc+0xdc>
 906:	74a2                	ld	s1,40(sp)
 908:	6a42                	ld	s4,16(sp)
 90a:	6aa2                	ld	s5,8(sp)
 90c:	6b02                	ld	s6,0(sp)
      if(p->s.size == nunits)
 90e:	fae90fe3          	beq	s2,a4,8cc <malloc+0x76>
        p->s.size -= nunits;
 912:	4137073b          	subw	a4,a4,s3
 916:	c798                	sw	a4,8(a5)
        p += p->s.size;
 918:	02071693          	slli	a3,a4,0x20
 91c:	01c6d713          	srli	a4,a3,0x1c
 920:	97ba                	add	a5,a5,a4
        p->s.size = nunits;
 922:	0137a423          	sw	s3,8(a5)
      freep = prevp;
 926:	00000717          	auipc	a4,0x0
 92a:	6ca73d23          	sd	a0,1754(a4) # 1000 <freep>
      return (void*)(p + 1);
 92e:	01078513          	addi	a0,a5,16
  }
}
 932:	70e2                	ld	ra,56(sp)
 934:	7442                	ld	s0,48(sp)
 936:	7902                	ld	s2,32(sp)
 938:	69e2                	ld	s3,24(sp)
 93a:	6121                	addi	sp,sp,64
 93c:	8082                	ret
 93e:	74a2                	ld	s1,40(sp)
 940:	6a42                	ld	s4,16(sp)
 942:	6aa2                	ld	s5,8(sp)
 944:	6b02                	ld	s6,0(sp)
 946:	b7f5                	j	932 <malloc+0xdc>
