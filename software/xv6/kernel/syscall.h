// System call numbers
#define SYS_fork   1
#define SYS_exit   2
#define SYS_wait   3
#define SYS_pipe   4
#define SYS_read   5
#define SYS_kill   6
#define SYS_exec   7
#define SYS_fstat  8
#define SYS_chdir  9
#define SYS_dup    10
#define SYS_getpid 11
#define SYS_sbrk   12
#define SYS_pause  13
#define SYS_uptime 14
#define SYS_open   15
#define SYS_write  16
#define SYS_mknod  17
#define SYS_unlink 18
#define SYS_link   19
#define SYS_mkdir  20
#define SYS_close  21
#define SYS_sync   22
#define SYS_getcpu 23   // MC-M3: the hart the caller is running on (test instrumentation)
#define SYS_pin    24
#define SYS_mtime  25   // MC-PERF: read-only shared CLINT mtime (measurement kernel; RV64 aligned 64-bit MMIO read in S-mode)   // MC-M3: test-only controlled scheduling -- run only on hart h (-1 = any); refused if h >= harts started
