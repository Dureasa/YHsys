#define NPROC        64  // maximum number of processes
#define NCPU          1  // single-core kernel
#define NOFILE       16  // open files per process
#define NFILE       100  // open files per system
#define NINODE       50  // maximum number of active i-nodes
#define NDEV         10  // maximum major device number
#define ROOTDEV       1  // device number of file system root disk
#define MAXARG       32  // max exec arguments
#define MAXOPBLOCKS  10  // max # of blocks any FS op writes
#define LOGBLOCKS    (MAXOPBLOCKS*3)  // max data blocks in on-disk log
#define NBUF         (MAXOPBLOCKS*3)  // size of disk block cache
#define FSSIZE       2000  // size of file system in blocks
#define MAXPATH      128   // maximum file path name
#define USERSTACK    1     // user stack pages

// ASLR randomization window sizes (in pages).
#define ASLR_CODE_MAX_PAGES      2
#define ASLR_STACK_GAP_MAX_PAGES 1
#define ASLR_HEAP_GAP_MAX_PAGES  0

// MLFQ scheduler configuration.
#define MLFQ_LEVELS      3
#define MLFQ_Q0_SLICE    1
#define MLFQ_Q1_SLICE    2
#define MLFQ_Q2_SLICE    4
#define MLFQ_BOOST_TICKS 64

