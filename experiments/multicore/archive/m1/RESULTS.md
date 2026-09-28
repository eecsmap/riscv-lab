# MC-M1 test results

Assembled 2026-09-26T16:31:22Z from `experiments/multicore/m1/runs/`.

| test | result | evidence | notes |
| --- | --- | --- | --- |
| T1.1 mhartid = HART_ID (0, 5, negative control) | TEACHING-MC1-HARTID-OK TEACHING-MC1-HARTID-OK TEACHING-MC1-HARTID-FAIL  | `runs/t1.1-hartid/*/run.txt` | third must be FAIL |
| T1.2 unit benches (worktree RTL) | TLB_TB_OK ICACHE_TB_OK IFILL_TB_OK XLATE_AMO_TB_OK  | `runs/t1.2-unit-benches/*.log` |  |
| T1.3 stable observation lint | LINT_STABLE_OBS fails=0 | `runs/t1.3-lint.txt` | planted reference caught |
| T1.9 unsupported configurations refuse |  Pipeline:refused Dual:refused Zero:refused | `runs/gen-unsupported-*/gen.log` | message names the value |
| elaboration gen-before-xv6fast | GEN_OK ed021fc06606fc51 | `runs/gen-before-xv6fast/gen.txt` | wall_s=31 |
| elaboration gen-before-boot | GEN_OK 12fffa5c2348dff0 | `runs/gen-before-boot/gen.txt` | wall_s=38 |
| elaboration gen-after-xv6fast | GEN_OK c36829afc4e3c6cd | `runs/gen-after-xv6fast/gen.txt` | wall_s=27 |
| elaboration gen-after-boot | GEN_OK 5c2801ed9d07d0f2 | `runs/gen-after-boot/gen.txt` | wall_s=39 |
| T1.4 core suite su (tag RTL) | CPU_SU_DONE fails=9 | `runs/t1.4-core-su-tag.log` |  |
| T1.4 core suite su (mine RTL) | CPU_SU_DONE fails=9 | `runs/t1.4-core-su-mine.log` |  |
| T1.4 core suite sv39 (tag RTL) | CPU_SV39_DONE fails=0 | `runs/t1.4-core-sv39-tag.log` |  |
| T1.4 core suite sv39 (mine RTL) | CPU_SV39_DONE fails=0 | `runs/t1.4-core-sv39-mine.log` |  |
| T1.4 core suite a (tag RTL) | CPU_A_DONE scenarios=17 infra=0 fails=0 | `runs/t1.4-core-a-tag.log` |  |
| T1.4 core suite a (mine RTL) | CPU_A_DONE scenarios=17 infra=0 fails=0 | `runs/t1.4-core-a-mine.log` |  |
| T1.4 core suite m (tag RTL) | CPU_M_DONE fails=6 | `runs/t1.4-core-m-tag.log` |  |
| T1.4 core suite m (mine RTL) | CPU_M_DONE fails=6 | `runs/t1.4-core-m-mine.log` |  |
| T1.4 core suite c (tag RTL) | CPU_C_DONE fails=16 | `runs/t1.4-core-c-tag.log` |  |
| T1.4 core suite c (mine RTL) | CPU_C_DONE fails=16 | `runs/t1.4-core-c-mine.log` |  |
| T1.5 atomic SoC subset (TeachingCpuV2 path) | 4 scored; ATOMIC_SOC_SUBSET scenarios=4 infra=0 score_fails=0 | `runs/atomic-soc-subset/*/score.txt` |  |
| probes before-fast | 18/18 programs OK/PASS, exit 0: 18 | `runs/probes-before-fast/summary-recovered.txt` |  |
| probes after-fast | 18/18 programs OK/PASS, exit 0: 18 | `runs/probes-after-fast/summary-recovered.txt` |  |
| probes before-trace | 13/13 programs OK/PASS, exit 0: 13 | `runs/probes-before-trace/summary-recovered.txt` |  |
| probes after-trace | 13/13 programs OK/PASS, exit 0: 13 | `runs/probes-after-trace/summary-recovered.txt` |  |
| T1.7 compare (fast) | 18 programs same on marker/exit/console; COMPARE fails=1 | `runs/compare-fast-recovered.txt` | the single fail is the programs-hash check: boot11/boot12 ELF metadata (gcc temp object names); load images identical |
| T1.7 compare (trace) | 13 programs same on marker/exit/console/commits; COMPARE fails=1 | `runs/compare-trace-recovered.txt` | the single fail is the programs-hash check: boot11/boot12 ELF metadata (gcc temp object names); load images identical |
| T1.8 ROI before->after | ROI_COMPARE rois=12 nonzero_delta=0 refused=0 | `runs/roi-compare.txt` |  |
| T1.6 R-BOOT gates (before) | RBOOT_DONE fails=0 infra=0 | `runs/rboot-before.log` |  |
| T1.6 R-BOOT gates (after) | RBOOT_DONE fails=0 infra=0 | `runs/rboot-after.log` |  |
| closeout 5: checker mutation self-test | CHECKER_SELFTEST pass=16 fail=0 | `runs/checker-selftest.txt` | each mutation rejected for its planted reason |
| closeout 4: hartid tb (exit-code verdicts, omitted default) | HARTID_TB pass=4 fail=0; omitted-default:exit0 explicit-0:exit0 nonzero-5:exit0 negctl-5-vs-0:exit134  | `runs/t1.1-hartid-closeout/*/run.txt` | negative control must exit 134 via $fatal |
| closeout rerun (fast, frozen ELFs, fixed entry point) | 13 programs ok/ok/same; COMPARE fails=0 | `runs/closeout2-compare-fast.txt` | programs (load-semantic identity): identical |
| closeout rerun (trace, frozen ELFs, fixed entry point) | 13 programs ok/ok/same; COMPARE fails=0 | `runs/closeout2-compare-trace.txt` | programs (load-semantic identity): identical |
| re-evaluation of the ORIGINAL records (fast) | 18 programs ok/ok/same; COMPARE fails=2 | `runs/reeval-fast.txt` | rejects are the input-identity checks only (per-run ELF builds, no load digest then) |
| re-evaluation of the ORIGINAL records (trace) | 13 programs ok/ok/same; COMPARE fails=2 | `runs/reeval-trace.txt` | rejects are the input-identity checks only (per-run ELF builds, no load digest then) |
| T1.10 xv6 b0apps (wrapper) | XV6_RC=0 wall=2609s; XV6_CHECK segments=4 prompts=4 stages=6 console_bytes=625 fails=0; checksums 5ADF55920BF7696 88133D5BD386DB60 62E55F5326378000  | `runs/xv6-after/run/` |  |
