#!/usr/bin/env python3
"""Every key source line the CONTRACT cites contains what the text says it does. Run from the worktree root."""
import os, sys
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../..'))
C = [('rtl/cpu/tcpu_core.v',15,'TLB_ENTRIES'),('rtl/cpu/tcpu_core.v',16,'ICACHE_BYTES'),('rtl/cpu/tcpu_core.v',48,') ('),('rtl/cpu/tcpu_core.v',104,');'),
 ('rtl/cpu/tcpu_core.v',71,'observation'),('rtl/cpu/tcpu_core.v',184,'resv_clear'),('rtl/cpu/tcpu_core.v',366,'WFI'),('rtl/cpu/tcpu_core.v',461,'resp_ready'),
 ('rtl/cpu/tcpu_core.v',473,'irq_take'),('rtl/cpu/tcpu_core.v',481,'CSR file'),('rtl/cpu/tcpu_core.v',593,'irq_take'),('rtl/cpu/tcpu_core.v',597,'trap_interrupt'),
 ('rtl/cpu/tcpu_core.v',607,'OPT01'),('rtl/cpu/tcpu_core.v',646,'second parcel'),('rtl/cpu/tcpu_core.v',658,'pc2'),('rtl/cpu/tcpu_core.v',795,'CPU-M: the long operation'),
 ('rtl/cpu/tcpu_core.v',798,'S_MUL'),('rtl/cpu/tcpu_core.v',805,'S_WB'),('rtl/cpu/tcpu_core.v',288,'legality'),('rtl/cpu/tcpu_core.v',391,'illegal'),
 ('rtl/cpu/tcpu_tlb.v',85,'always @(*)'),('rtl/cpu/tcpu_tlb.v',96,'always @(posedge clk)'),('rtl/cpu/tcpu_tlb.v',111,'end'),
 ('rtl/cpu/tcpu_icache.v',57,'assign hit'),('rtl/cpu/tcpu_ifill.v',140,'FILL0'),('rtl/cpu/tcpu_ifill.v',156,'ans_data'),
 ('rtl/cpu/tcpu_muldiv.v',120,'count < 7'),('rtl/cpu/tcpu_muldiv.v',125,'done <='),('rtl/cpu/tcpu_regfile.v',21,'write_ok'),('rtl/cpu/tcpu_regfile.v',24,'rd2'),
 ('rtl/cpu/tcpu_ptw.v',3,'software-managed A/D'),('rtl/cpu/tcpu_csr.v',182,'pending & enabled'),('rtl/cpu/tcpu_csr.v',196,'irq_cause'),
 ('soc/scala/teaching/RD2BridgeV2.scala',84,'req.ready'),('soc/scala/teaching/RD2BridgeV2.scala',196,'resp.valid'),('soc/scala/teaching/RD2BridgeV2.scala',77,'assert(!(dFire'),
 ('soc/scala/teaching/RD2BridgeV2.scala',157,'source'),('soc/scala/teaching/RD2BridgeV2.scala',168,'req.fire()'),('soc/scala/teaching/RD2BridgeV2.scala',201,'resp.fire()'),
 ('soc/scala/teaching/RD2BridgeV2.scala',140,'markNow'),('soc/scala/teaching/RD2Soc.scala',269,'cpuRestartSafe'),('soc/scala/teaching/RD2Soc.scala',264,'CPU_RESTART_SAFE'),
 ('soc/scala/teaching/RD2Soc.scala',371,'awaitingRetire := true'),('soc/scala/teaching/RD2Soc.scala',372,'awaitingRetire := false'),('soc/scala/teaching/RD2Soc.scala',374,'busyAll'),
 ('soc/scala/teaching/RD2Soc.scala',502,'busy'),('soc/scala/teaching/RD2Soc.scala',503,'busyAll'),('soc/scala/teaching/RD2Soc.scala',58,'coreImpl'),('soc/scala/teaching/RD2Soc.scala',57,'numCores'),
 ('soc/scala/teaching/RD2Soc.scala',119,'coreImpl'),('soc/scala/teaching/RD2Soc.scala',121,'numCores'),('soc/scala/teaching/cpu_boot_main.cpp',67,'HOSTDONE'),('soc/scala/teaching/cpu_boot_main.cpp',76,'io_busy'),
 ('soc/scala/teaching/TeachingCpuBlackBox.scala',71,'desiredName'),('soc/scala/teaching/TeachingCpuBlackBox.scala',214,'TeachingCpuObs'),('soc/scala/teaching/TeachingCpuBlackBox.scala',233,'TeachingCpuImplObs'),
 ('tests/cpu/tb/tcpu_harness.v',55,'IRQ_ARM_REQUIRED'),('tests/cpu/tb/tcpu_harness.v',42,'IRQ_POINT'),('experiments/multicore/archive/m0/CONTRACT.md',55,'C2')]
ok = 0
for f, ln, tok in C:
    lines = open(os.path.join(R, f), errors='replace').read().split('\n')
    hit = ln - 1 < len(lines) and tok in lines[ln - 1]; ok += hit
    print(('ok  ' if hit else 'MISS'), f'{f}:{ln}', repr(tok), '' if hit else '-> ' + (lines[ln - 1][:90] if ln - 1 < len(lines) else 'EOF'))
print(f'ANCHORS {ok}/{len(C)}'); sys.exit(0 if ok == len(C) else 1)
