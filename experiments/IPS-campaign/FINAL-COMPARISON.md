# Cumulative comparison — SIMULATOR, 40 MHz configured, never pooled with board results

| workload / ROI | baseline CPI | fetch32 CPI | tlb CPI | cache CPI | IPS@40MHz (cache) | vs baseline | vs previous stage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `perf02_sv39/bare_alu` | 19.02 | 11.00 | 11.00 | 6.00 | 6,666,148 | **3.170x** | 1.833x |
| `perf02_sv39/bare_load` | 21.36 | 13.35 | 13.35 | 8.34 | 4,798,036 | **2.562x** | 1.601x |
| `perf02_sv39/k4_alu` | 71.04 | 37.04 | 13.01 | 8.00 | 5,000,000 | **8.880x** | 1.626x |
| `perf02_sv39/k4_load` | 82.12 | 48.06 | 16.02 | 11.00 | 3,636,419 | **7.465x** | 1.457x |
| `perf02_sv39/mega_alu` | 39.05 | 21.06 | 13.01 | 8.00 | 5,000,000 | **4.881x** | 1.626x |
| `perf02_sv39/mega_load` | 44.67 | 26.70 | 16.02 | 11.00 | 3,636,419 | **4.061x** | 1.456x |
| `perf03_fetch/insn16` | 11.00 | 11.00 | 11.00 | 6.00 | 6,666,037 | **1.833x** | 1.833x |
| `perf03_fetch/insn32` | 19.02 | 11.00 | 11.00 | 6.00 | 6,666,148 | **3.170x** | 1.833x |
| `perf04_where/load_clint` | 21.36 | 13.34 | 13.34 | 8.33 | 4,800,090 | **2.563x** | 1.601x |
| `perf04_where/load_dram` | 21.36 | 13.34 | 13.34 | 8.34 | 4,798,036 | **2.562x** | 1.601x |
| `perf06_iws/iws_exceeds` | 19.02 | 11.00 | 11.00 | 9.52 | 4,200,158 | **1.997x** | 1.155x |
| `perf06_iws/iws_resident` | 19.02 | 11.00 | 11.00 | 6.00 | 6,664,667 | **3.169x** | 1.833x |

External AXI reads per binary:

| workload | baseline | fetch32 | tlb | cache | baseline → cache |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf02_sv39` | 1,081,139 | 584,225 | 248,937 | 50,421 | **95.3% fewer** |
| `perf03_fetch` | 107,348 | 74,407 | 74,407 | 5,118 | **95.2% fewer** |
| `perf04_where` | 150,962 | 83,272 | 83,272 | 17,076 | **88.7% fewer** |
| `perf06_iws` | 306,618 | 156,607 | 156,607 | 46,104 | **85.0% fewer** |
