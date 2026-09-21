# How much of the boot is proportional to PHYSTOP

`kinit()` frees every page between the end of the kernel and `PHYSTOP`, and `kvminit()` maps all of that
same range page by page through `walk()`. Both scale with `PHYSTOP`, and on a core where every instruction
fetch is a DRAM access they are not cheap. The baseline already tuned this down for simulation (128 MiB on
the board, 16 MiB here); the question is whether 16 MiB is still more than the boot needs.

Measured on the same simulator (`sim-nomon3`), same disk image, same kernel apart from the one constant,
at the same milestone — the console line `blkdev: 4000 sectors (1 MB), max request 16 sectors`, which comes
after `kinit` and `kvminit` and before anything that does not scale with memory size:

| `PHYSTOP` | cycles to the milestone | instructions retired | free pages after the kernel |
|---|---|---|---|
| `KERNBASE + 16 MiB` (the baseline) | 40,000,000 | 2,591,340 | ~4060 |
| `KERNBASE + 4 MiB` | 26,000,000 | 1,696,284 | ~990 |
| `KERNBASE + 2 MiB` | 24,000,000 | 1,552,313 | ~480 |

* 16 → 4 MiB removes **35%** of the cycles and of the instructions up to that milestone: about 0.9 M
  instructions and 14 M cycles. Against the whole run to the point where the boot is currently blocked
  (5.26 M instructions, 192 M cycles) that is ~17% of the instructions and ~7% of the cycles — the phases
  after this milestone do not scale with memory.
* 2 MiB buys only 2 M cycles more than 4 MiB while halving the headroom, so 4 MiB is the better stopping
  point.

4 MiB leaves ~990 free pages after the 132 KiB kernel. init, sh and a command are a handful of pages each,
the 64 kernel stacks are one page each, and the buffer cache is static in `bss`, so this is comfortable for
the stages this task asks for. It is not enough for `usertests`, which is out of scope here and out of
reach on this simulator anyway.

Raw runs: `evidence/run-4mb.log`, `evidence/run-2mb.log`. The delivered `xv6-teaching` tree still has the
baseline's 16 MiB — this is a measurement and a proposal, not a change, because the delegation limits the
teaching copy's source differences to the two PMP lines.
