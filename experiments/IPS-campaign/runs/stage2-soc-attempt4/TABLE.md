| workload | ROI | baseline | fetch32 | tlb | tlboff | tlb gain vs baseline | tlb gain vs fetch32 | tlboff == fetch32 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | :---: |
| `perf02_sv39` | `bare_alu` | 19.02 | 11.00 | **11.00** | 11.00 | 1.729x | 1.000x | YES |
| `perf02_sv39` | `bare_load` | 21.36 | 13.35 | **13.35** | 13.35 | 1.600x | 1.000x | YES |
| `perf02_sv39` | `k4_alu` | 71.04 | 37.04 | **13.01** | 37.04 | 5.462x | 2.848x | YES |
| `perf02_sv39` | `k4_load` | 82.12 | 48.06 | **16.02** | 48.06 | 5.125x | 3.000x | YES |
| `perf02_sv39` | `mega_alu` | 39.05 | 21.06 | **13.01** | 21.06 | 3.002x | 1.619x | YES |
| `perf02_sv39` | `mega_load` | 44.67 | 26.70 | **16.02** | 26.70 | 2.788x | 1.667x | YES |
| `perf03_fetch` | `insn16` | 11.00 | 11.00 | **11.00** | 11.00 | 1.000x | 1.000x | YES |
| `perf03_fetch` | `insn32` | 19.02 | 11.00 | **11.00** | 11.00 | 1.729x | 1.000x | YES |
| `perf04_where` | `load_clint` | 21.36 | 13.34 | **13.34** | 13.34 | 1.601x | 1.000x | YES |
| `perf04_where` | `load_dram` | 21.36 | 13.34 | **13.34** | 13.34 | 1.601x | 1.000x | YES |
| `perf06_iws` | `iws_exceeds` | 19.02 | 11.00 | **11.00** | 11.00 | 1.729x | 1.000x | YES |
| `perf06_iws` | `iws_resident` | 19.02 | 11.00 | **11.00** | 11.00 | 1.729x | 1.000x | YES |
