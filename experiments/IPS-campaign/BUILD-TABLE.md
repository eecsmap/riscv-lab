| stage | WNS (ns) | WHS (ns) | setup fail | hold fail | LUT | FF | BRAM | DSP | critical warnings | bitstream |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `baseline` | **0.779** | 0.024 | 0 | 0 | 13,777 | 5,884 | 0 | 0 | 0 | `423f7d227a4ae0a5` |
| `fetch32` | **0.733** | 0.020 | 0 | 0 | 13,841 | 5,880 | 0 | 0 | 0 | `0cf25aee6b9ed564` |
| `tlb` | **0.273** | 0.037 | 0 | 0 | 14,092 | 6,685 | 0 | 0 | 0 | `5add000a9c6c5e86` |
| `cache` | **0.354** | 0.035 | 0 | 0 | 14,529 | 7,007 | 0 | 0 | 0 | `d926c09abe3a370c` |

Incremental cost, each stage against its predecessor:

| stage | ΔLUT | ΔFF | ΔWNS (ns) |
| --- | ---: | ---: | ---: |
| `fetch32` | +64 | -4 | -0.046 |
| `tlb` | +251 | +805 | -0.460 |
| `cache` | +437 | +322 | +0.081 |
