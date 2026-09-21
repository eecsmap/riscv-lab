/* Compute the three B0 workloads' expected checksums with identical integer semantics to the xv6
   programs. Pure uint64 arithmetic and byte patterns, so the host and the target must agree. */
#include <stdio.h>
#include <stdint.h>
#define C_ITERS 200000
#define A_N 16384
#define A_PASSES 8
#define A_STRIDE 7
#define F_BLOCK 512
#define F_BLOCKS 64
static uint64_t a[A_N];
static char buf[F_BLOCK];
int main(void){
  uint64_t x = 88172645463325252ULL;
  for (int i=0;i<C_ITERS;i++){ x^=x<<13; x^=x>>7; x^=x<<17; x+=(uint64_t)i; }
  printf("B0-COMPUTE-CHECKSUM=%lx\n",(unsigned long)x);
  for (int i=0;i<A_N;i++) a[i]=(uint64_t)i*2654435761ULL;
  uint64_t sum=0; int idx=0;
  for (int p=0;p<A_PASSES;p++) for(int i=0;i<A_N;i++){ sum+=a[idx]; a[idx]^=sum>>3; idx=(idx+A_STRIDE)%A_N; }
  printf("B0-ARRAY-CHECKSUM=%lx\n",(unsigned long)sum);
  uint64_t fs=0;
  for (int b=0;b<F_BLOCKS;b++){
    for(int i=0;i<F_BLOCK;i++) buf[i]=(char)((b*31+i*7)&0xff);
    for(int i=0;i<F_BLOCK;i++) fs=fs*131+(unsigned char)buf[i];
  }
  printf("B0-FILE-CHECKSUM=%lx\n",(unsigned long)fs);
  return 0;
}
