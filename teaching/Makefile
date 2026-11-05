# Teaching steps: `make stepN` runs step N's tests against the core in $(CORE); `make stepN-mutants` runs the
# fault injections that step N's tests must catch; `make stepN-all` is both.
#
#   make step1-init                    # copy the step-1 skeleton and the given regfile into teaching/work/cpu
#   make step1                         # your core: teaching/work/cpu/*.v (default CORE)
#   make step1-all CORE=../rtl/cpu     # the reference core, which every step must pass
#
# Needs: iverilog, python3, and a riscv64 GCC (riscv64-unknown-elf- or riscv64-linux-gnu-; or TOOLPREFIX=).
TEACH := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
export ROOT := $(abspath $(TEACH)/..)
export CORE ?= $(TEACH)/work/cpu
export OUT  ?= $(TEACH)/out

ifndef TOOLPREFIX
TOOLPREFIX := $(shell for p in riscv64-unknown-elf- riscv64-elf- riscv64-none-elf- riscv64-linux-gnu-; do \
                command -v $${p}gcc >/dev/null 2>&1 && { echo $$p; break; }; done)
endif
ifeq ($(TOOLPREFIX),)
$(error no riscv64 GCC found; set TOOLPREFIX=/path/to/riscv64-unknown-elf-)
endif
export CC := $(TOOLPREFIX)gcc
export OBJCOPY := $(TOOLPREFIX)objcopy
export NM := $(TOOLPREFIX)nm
RUN := $(TEACH)/tools/run-test.sh

# Which extensions the core under test has. Some step-3 expectations depend on it (mepc alignment, misa, the
# mstatus bits, whether a 2-byte-aligned jump target traps). A student's core has none until the step that
# adds it; the reference core has them all, and is detected by path. Override on the command line:
#   make step3 ISA_FLAGS="-DHAS_S"           after step 6
REF_ISA   := -DHAS_C -DHAS_S -DHAS_M
ISA_FLAGS ?= $(if $(filter $(abspath $(CORE)),$(ROOT)/rtl/cpu),$(REF_ISA),)
ISA_CF    := $(foreach f,$(ISA_FLAGS),--cflag $(f))

.PHONY: all clean unit step1-init step1 step1-mutants step1-all step2 step2-mutants step2-all step3 step3-mutants step3-all step4 step4-mutants step4-all step5-sim step5 step5-run pl-sim oled-sim oled-fw-sim mcu0-sim mcu0-fw mcu0-bit mcu0-prog

all: step1-all

# ---- unit tests: every work/unit/tb_*.v is compiled with the core's sources and run on its own --------------
# A unit test prints RESULT PASS or RESULT FAIL; `make unit` fails if any does not pass.
UNIT_DIR := $(TEACH)/work/unit
unit:
	@echo "== unit: $(UNIT_DIR)/tb_*.v (CORE=$(CORE))"
	@ls $(UNIT_DIR)/tb_*.v >/dev/null 2>&1 || { echo "no unit tests in $(UNIT_DIR)"; exit 1; }
	@mkdir -p $(OUT)/unit; fail=0; \
	for tb in $(UNIT_DIR)/tb_*.v; do n=$$(basename $$tb .v); \
	  iverilog -g2005 -I $(ROOT)/rtl/cpu -I $(CORE) -s $$n -o $(OUT)/unit/$$n.vvp $$tb $(CORE)/*.v || { echo "  FAIL  $$n  (compile)"; fail=1; continue; }; \
	  vvp -n $(OUT)/unit/$$n.vvp > $(OUT)/unit/$$n.log 2>&1; \
	  if grep -q '^RESULT PASS' $(OUT)/unit/$$n.log; then echo "  ok    $$n  $$(grep -v -E 'RESULT|finish called' $(OUT)/unit/$$n.log | tail -1)"; \
	  else echo "  FAIL  $$n  -- $(OUT)/unit/$$n.log"; grep -m5 -E 'MISMATCH|ERROR|FAIL' $(OUT)/unit/$$n.log | sed 's/^/        /'; fail=1; fi; \
	done; exit $$fail

# ---- step 1: the first instructions retire (addi, auipc, sd, jal; 4-byte aligned fetch) --------------------
# step1-init: your starting point. Refuses to overwrite a tcpu_core.v you have already begun.
step1-init:
	@mkdir -p $(TEACH)/work/cpu
	@if [ -e $(TEACH)/work/cpu/tcpu_core.v ]; then echo "work/cpu/tcpu_core.v exists; not overwriting"; \
	 else cp $(TEACH)/step1/tcpu_core_skeleton.v $(TEACH)/work/cpu/tcpu_core.v && echo "copied skeleton -> work/cpu/tcpu_core.v"; fi
	@[ -e $(TEACH)/work/cpu/tcpu_regfile.v ] || { cp $(ROOT)/rtl/cpu/tcpu_regfile.v $(TEACH)/work/cpu/ && echo "regfile -> work/cpu/tcpu_regfile.v (given)"; }
	@echo "now: fill the TODOs in work/cpu/tcpu_core.v, then: make step1"
step1:
	@echo "== step1: tests (CORE=$(CORE))"
	@$(RUN) step1 $(TEACH)/step1/s1_tohost.S rv64i plain
	@$(RUN) step1 $(TEACH)/step1/s1_tohost.S rv64i slow -P READY_DELAY=3 -P RESP_DELAY=5
	@$(RUN) step1 $(TEACH)/step1/s1_tohost.S rv64i random -P RANDOM=1 -P SEED=7
step1-mutants:
	@echo "== step1: mutants that the port monitor must catch (CORE=$(CORE))"
	@$(RUN) --expect FAIL --grep 'PROTO ERROR: request withdrawn before the handshake' \
	    step1 $(TEACH)/step1/s1_tohost.S rv64i withdraw -P REQ_WITHDRAW=1 -P READY_DELAY=2
step1-all: step1 step1-mutants

# ---- step 2: the whole of RV64I --------------------------------------------------------------------------------
# t01..t03 are the step's own tests; d03 and d06 come from tests/cpu/tests. All define `main`; dcrt.S is the crt.
CRT2 := --crt $(ROOT)/tests/cpu/tests/dcrt.S
S2   := $(TEACH)/step2
D    := $(ROOT)/tests/cpu/tests
step2:
	@echo "== step2: tests (CORE=$(CORE))"
	@$(RUN) $(CRT2) step2 $(S2)/t01_alu.S    rv64i_zifencei plain
	@$(RUN) $(CRT2) step2 $(S2)/t01_alu.S    rv64i_zifencei random -P RANDOM=1 -P SEED=3
	@$(RUN) $(CRT2) step2 $(S2)/t02_branch.S rv64i_zifencei plain
	@$(RUN) $(CRT2) step2 $(S2)/t02_branch.S rv64i_zifencei random -P RANDOM=1 -P SEED=5
	@$(RUN) $(CRT2) step2 $(S2)/t03_ldst.S   rv64i_zifencei plain
	@$(RUN) $(CRT2) step2 $(S2)/t03_ldst.S   rv64i_zifencei slow -P READY_DELAY=2 -P RESP_DELAY=4
	@$(RUN) $(CRT2) step2 $(D)/d03_badbranch.S  rv64i_zifencei plain
	@$(RUN) $(CRT2) step2 $(D)/d06_loadpayload.S rv64i_zifencei plain
step2-mutants:
	@echo "== step2: mutants (CORE=$(CORE))"
	@$(RUN) --expect FAIL --grep 'TOHOST code=1$$' $(CRT2) step2 $(S2)/t01_alu.S  rv64i_zifencei x0     -P X0_WRITABLE=1
	@$(RUN) --expect FAIL --grep 'TOHOST code=2$$' $(CRT2) step2 $(S2)/t03_ldst.S rv64i_zifencei nosext -P NO_LOAD_SEXT=1
	@$(RUN) --expect FAIL --grep 'PROTO ERROR: read request carried a write payload' \
	    $(CRT2) step2 $(D)/d06_loadpayload.S rv64i_zifencei leak -P LOAD_WDATA_LEAK=1
step2-all: step2 step2-mutants

# ---- step 3: synchronous exceptions, the M-mode CSRs, mret ------------------------------------------------------
# d tests end in a trap (STOP_ON_TRAP=1, +expect_trap); c tests run through the shared handler thandler.S.
# c07 is a negative control: its handler faults on every entry, and the run must be rejected as a TRAP STORM.
S3   := $(TEACH)/step3
T2   := $(ROOT)/tests/cpu/tests2
CRTH := --crt $(ROOT)/tests/cpu/tests/dcrt.S --crt $(T2)/thandler.S
M3   := rv64i_zicsr_zifencei
TRAP := -P STOP_ON_TRAP=1 --plus
MUT  ?=                                  # extra run-test options applied to every step-3 run, e.g. MUT="-P TRAP_BAD_MEPC=1" (kill matrix)
step3:
	@echo "== step3: tests (CORE=$(CORE) ISA_FLAGS=$(ISA_FLAGS))"
	@$(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=7 --grep 'HALT cause=7 .* data_requests=0' step3 $(D)/d01_highpa.S $(M3) plain
	@$(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=4 --grep 'HALT cause=4 .* data_requests=0' step3 $(D)/d02_misaligned.S $(M3) plain
	@$(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=2 --nogrep 'COMMIT .* insn=0000007b' step3 $(D)/d04_illegal.S $(M3) plain
	@for n in 1 2 3 4 5 6 7; do $(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=2 --cflag -DJALR_F3=$$n --grep 'REG x9=000000005a5a5a5a' \
	    step3 $(D)/d05_jalr_illegal.S $(M3) f3_$$n || exit 1; done
	@$(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=2 --grep 'REG x9=000000005a5a5a5a' step3 $(S3)/d07_csr_time.S $(M3) plain
	@$(RUN) $(MUT) $(CRT2) $(TRAP) expect_trap=1 --grep 'HALT cause=1 .* tval=0000000100000000 data_requests=0' step3 $(S3)/d09_pc_highpa.S $(M3) plain
	@$(RUN) $(MUT) $(CRT2) step3 $(D)/d08_minstret_ok.S $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c01_csrforms.S     $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(S3)/c02_warl.S         $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(S3)/c03_csr_illegal.S  $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c04_counters.S     $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c05_mret_count.S   $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(S3)/c06_targets.S      $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c08_accessfault.S  $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c09_ecall_ebreak.S $(M3) plain --nogrep 'COMMIT .* insn=00000073' --nogrep 'COMMIT .* insn=00100073'
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c10_trapcount.S    $(M3) plain
	@$(RUN) $(MUT) $(CRTH) $(ISA_CF) step3 $(T2)/c10_trapcount.S    $(M3) random -P RANDOM=1 -P SEED=11
	@$(RUN) $(MUT) $(CRTH) --expect FAIL --grep 'TRAP STORM' step3 $(T2)/c07_handler_fault.S $(M3) storm
step3-mutants:
	@echo "== step3: mutants (CORE=$(CORE))"
	@$(RUN) --expect FAIL --grep 'TOHOST code=1$$' $(CRTH) $(ISA_CF) step3 $(T2)/c09_ecall_ebreak.S $(M3) badmepc   -P TRAP_BAD_MEPC=1
	@$(RUN) --expect FAIL --grep 'TOHOST code=1$$' $(CRTH) $(ISA_CF) step3 $(T2)/c10_trapcount.S   $(M3) countsret -P TRAP_COUNTS_RET=1
	@$(RUN) --expect FAIL --grep 'TOHOST code=1$$' $(CRTH) $(ISA_CF) step3 $(S3)/c03_csr_illegal.S $(M3) rowrite   -P ALLOW_RO_WRITE=1
step3-all: step3 step3-mutants

# ---- step 4: interrupts (mie, mip, three level lines, wfi), accepted only at the architectural boundary ---------
# Every run checks the injection context the bench prints: the chosen moment occurred (hits > 0), the line was
# raised once (fires=1) and quieted by the handler (clears=N), and for the placed injections the core state, the
# pc it was aimed at and whether the enables were really in effect. @SYM@ is the address of a label in the test.
# State numbers are the shared encodings: 1 IF_WAIT, 4 MEM_WAIT, 5 WB, 8 ARCH.
S4   := $(TEACH)/step4
CRTI := --crt $(ROOT)/tests/cpu/tests/dcrt.S --crt $(T2)/ihandler.S
IRQ  := -P IRQ_LINE=1
ONE  := 'IRQ hits=[1-9][0-9]* fires=1 clears=1 '
ARMD := -P IRQ_ARM_REQUIRED=1 -P IRQ_NEED_ENABLED=1
J01  := $(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) $(ARMD)
J02  := -P IRQ_POINT=4 -P IRQ_ARM_REQUIRED=1 -P IRQ_NEED_WRITE=1 --watch watch_slot
SLOW := -P READY_DELAY=2 -P RESP_DELAY=4
step4:
	@echo "== step4: tests (CORE=$(CORE) ISA_FLAGS=$(ISA_FLAGS))"
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 --grep $(ONE) step4 $(T2)/i01_basic.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 -P RANDOM=1 -P SEED=9 --grep $(ONE) step4 $(T2)/i01_basic.S $(M3) random
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) -P IRQ_ALL_LINES=1 -P IRQ_POINT=2 --grep 'IRQ hits=[1-9][0-9]* fires=1 clears=3 ' step4 $(T2)/i02_priority.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 --grep $(ONE) step4 $(T2)/i03_masking.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 --grep $(ONE) step4 $(S4)/i04_mip_level.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 --grep $(ONE) step4 $(T2)/i05_wfi.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 --grep $(ONE) step4 $(T2)/i06_mret_reenter.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=6 -P IRQ_ARM_REQUIRED=1 --grep $(ONE)'fire_state=5 .* fire_enabled=1' step4 $(T2)/i07_epc_redirect.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=4 --grep $(ONE)'fire_state=4 fire_pc=@the_bad_load@ fire_enabled=1 fire_outstanding=1' step4 $(T2)/i08_sync_first.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=3 --grep $(ONE)'fire_state=4 .* fire_outstanding=0' step4 $(T2)/i09_store_exact.S $(M3) req
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=4 --grep $(ONE)'fire_state=4 .* fire_outstanding=1' step4 $(T2)/i09_store_exact.S $(M3) resp
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=4 -P READY_DELAY=2 -P RESP_DELAY=4 --grep $(ONE)'fire_state=4 .* fire_outstanding=1' step4 $(T2)/i09_store_exact.S $(M3) slow
	@$(J01) -P IRQ_POINT=1 --grep $(ONE)'fire_state=1 fire_pc=@target_insn@ fire_enabled=1 fire_outstanding=0' step4 $(T2)/j01_enabled_boundary.S $(M3) if_req
	@$(J01) -P IRQ_POINT=2 --grep $(ONE)'fire_state=1 fire_pc=@target_insn@ fire_enabled=1 fire_outstanding=1' step4 $(T2)/j01_enabled_boundary.S $(M3) if_resp
	@$(J01) -P IRQ_POINT=3 --grep $(ONE)'fire_state=4 fire_pc=@target_insn@ fire_enabled=1 fire_outstanding=0' step4 $(T2)/j01_enabled_boundary.S $(M3) mem_req
	@$(J01) -P IRQ_POINT=4 --grep $(ONE)'fire_state=4 fire_pc=@target_insn@ fire_enabled=1 fire_outstanding=1' step4 $(T2)/j01_enabled_boundary.S $(M3) mem_resp
	@$(J01) -P IRQ_POINT=5 --grep $(ONE)'fire_state=5 fire_pc=@target_insn@ fire_enabled=1 fire_outstanding=0' step4 $(T2)/j01_enabled_boundary.S $(M3) wb
	@$(J01) -P IRQ_POINT=7 --grep $(ONE)'fire_state=8 fire_pc=@after_target@ fire_enabled=1 fire_outstanding=0' step4 $(T2)/j01_enabled_boundary.S $(M3) arch
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=4 -P IRQ_ARM_REQUIRED=1 -P IRQ_NEED_WRITE=1 --watch watch_slot \
	    --grep $(ONE)'fire_state=4 fire_pc=@watched_store@ fire_enabled=1 fire_outstanding=1' \
	    --grep 'WATCH addr=@watch_slot@ req=102 wreq=51 resp=102 writes=51$$' step4 $(T2)/j02_store_once.S $(M3) plain
	@$(RUN) $(MUT) $(CRTI) $(ISA_CF) $(IRQ) $(J02) $(SLOW) --grep 'WATCH addr=@watch_slot@ req=102 wreq=51 resp=102 writes=51$$' \
	    step4 $(T2)/j02_store_once.S $(M3) slow
# EARLY_IRQ is killed two ways: on a fast bus it withdraws an unaccepted request (the port monitor, and mepc is the
# load that never ran); on a slow bus it abandons a store whose response is outstanding, the handler returns to that
# store and it runs twice -- invisible to the program, visible only in the watched-address counts.
# DUP_STORE is a control on the bench itself: the memory model applies one watched write twice and only `writes` sees it.
step4-mutants:
	@echo "== step4: mutants (CORE=$(CORE))"
	@$(RUN) --expect FAIL --grep 'TRAP .*epc=@trap_handler@ .*\(interrupt\)' $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=2 step4 $(T2)/i01_basic.S $(M3) stale -P STALE_MIE=1
	@$(RUN) --expect FAIL --grep 'TOHOST code=3$$' $(CRTI) $(ISA_CF) $(IRQ) -P IRQ_POINT=6 -P IRQ_ARM_REQUIRED=1 step4 $(T2)/i07_epc_redirect.S $(M3) badmepc -P IRQ_BAD_MEPC=1
	@$(RUN) --expect FAIL --grep 'PROTO ERROR: request withdrawn before the handshake' --grep 'TOHOST code=7$$' \
	    $(CRTI) $(ISA_CF) $(IRQ) $(ARMD) -P IRQ_POINT=1 step4 $(T2)/j01_enabled_boundary.S $(M3) early -P EARLY_IRQ=1
	@$(RUN) --grep 'WATCH addr=@watch_slot@ req=10[3-9] wreq=5[2-9] ' --nogrep 'wreq=51 ' \
	    $(CRTI) $(ISA_CF) $(IRQ) $(J02) $(SLOW) step4 $(T2)/j02_store_once.S $(M3) early_slow -P EARLY_IRQ=1
	@$(RUN) --grep 'WATCH addr=@watch_slot@ req=102 wreq=51 resp=102 writes=52$$' \
	    $(CRTI) $(ISA_CF) $(IRQ) $(J02) $(SLOW) step4 $(T2)/j02_store_once.S $(M3) dup_store -P DUP_STORE=1
step4-all: step4 step4-mutants

# ---- pure PL: the core on tcpu_bram_mem behind tcpu_pl_top, no harness (teaching/pl/README.md) --------------
PL_TEST ?= $(TEACH)/step1/s1_tohost.S
pl-sim:
	@echo "== pl-sim: tcpu_pl_top + BRAM memory, $(notdir $(PL_TEST)) (CORE=$(CORE))"
	@mkdir -p $(OUT)/pl
	@$(CC) -march=rv64i -mabi=lp64 -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--no-warn-rwx-segments \
	    -T $(ROOT)/software/probes/link.ld -o $(OUT)/pl/prog.elf $(PL_TEST)
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(OUT)/pl/prog.elf $(OUT)/pl/prog.hex $(OUT)/pl/prog.tohost >/dev/null
	@iverilog -g2005 -I $(ROOT)/rtl/cpu -I $(CORE) -o $(OUT)/pl/sim.vvp \
	    $(TEACH)/pl/tb_pl.v $(TEACH)/pl/tcpu_pl_top.v $(TEACH)/pl/tcpu_bram_mem.v $(CORE)/*.v
	@vvp -n $(OUT)/pl/sim.vvp +hex=$(OUT)/pl/prog.hex +tohost=$$(cat $(OUT)/pl/prog.tohost) $${VCD:+ +vcd=$(OUT)/pl/sim.vcd} \
	    > $(OUT)/pl/sim.log 2>&1; grep -E '^(SUMMARY|TOHOST|TIMEOUT|RESULT)' $(OUT)/pl/sim.log | tr '\n' ' '; echo
	@grep -q '^RESULT PASS' $(OUT)/pl/sim.log

# ---- step 5: your core inside the RD2 SoC (teaching/step5/README.md) ------------------------------------------
# step5-sim verilates the SoC with $(CORE) (one simulator per core directory, rebuilt when a core file changes);
# step5 runs the four boot programs and judges each with the accepted M3 checkers (teaching/step5/check).
S5SIM := $(OUT)/step5/sim-$(shell printf '%s' $(abspath $(CORE)) | md5sum | cut -c1-8)
S5RUN := $(TEACH)/tools/step5-run.sh $(S5SIM)/obj_dir/sim $(OUT)/step5
M3T   := $(ROOT)/tests/cpu/m3tests
S5C   := --exit=0 --assert-free --host-ok --exit-store-pc=@exit_store@ --tohost=@tohost@ --axi-min-reads=1 --axi-min-writes=1
$(S5SIM)/obj_dir/sim: $(wildcard $(CORE)/*.v) $(TEACH)/step5/sim/step5_main.cpp $(TEACH)/step5/sim/RD2Harness.RD2BootConfig.v.xz
	@echo "== step5-sim: verilating the SoC with CORE=$(CORE) (about 20 s)"
	@$(TEACH)/tools/step5-build-sim.sh $(CORE) $(S5SIM)
step5-sim: $(S5SIM)/obj_dir/sim
step5: step5-sim
	@echo "== step5: boot programs on the RD2 SoC (CORE=$(CORE))"
	@$(S5RUN) boot01_marker  $(M3T)/boot01_marker.S  -- $(S5C) --marker=TEACHING-CPU-M3-OK --irqs=1 --sync-traps=0
	@$(S5RUN) boot02_clint   $(M3T)/boot02_clint.S   -- $(S5C) --marker=M3-CLINT-OK --irqs=3 --sync-traps=0
	@$(S5RUN) boot03_ddr     $(M3T)/boot03_ddr.S     -- $(S5C) --marker=M3-DDR-OK --irqs=1 --sync-traps=0
	@$(S5RUN) boot04_badaddr $(M3T)/boot04_badaddr.S -- $(S5C) --marker=M3-BADADDR-OK --irqs=1 --sync-traps=1 \
	    --sync-cause=5 --sync-epc=0x@bad_load@ --sync-tval=0x50000000
# your own program: PROG=work/hello.c (C, with step5/crt.S and step5/console.h) or PROG=x.S (assembly, own _start)
PROG ?= step5/hello.c
step5-run: step5-sim
	@$(S5RUN) $(basename $(notdir $(PROG))) $(if $(filter %.c,$(PROG)),$(TEACH)/step5/crt.S) $(abspath $(PROG))
	@echo "---- console ($(OUT)/step5/$(basename $(notdir $(PROG))).console):"; cat $(OUT)/step5/$(basename $(notdir $(PROG))).console

# ---- MCU-0: core + router + RAM + CLINT + GPIO, firmware in C (teaching/mcu0/README.md) ------------------------
# APP picks the firmware, teaching/mcu0/$(APP).c:
#   blink      polled, RV64I only: runs on a step-2 core (start.S; objdump checks there are no CSR instructions)
#   irq_blink  LED0 from the timer interrupt: needs a step-4 core (trap_start.S; the testbench requires interrupts)
#   tasks      two tasks, preemptive round robin (task_start.S saves all registers); needs a step-4 core
MCU0 := $(TEACH)/mcu0
APP ?= blink
# oled_* apps that take interrupts (step-4 core); the other oled_* apps are polled RV64I like blink
OLED_IRQ_APPS := oled_snake
ifneq ($(filter $(OLED_IRQ_APPS),$(APP)),)
MCU0_CRT := $(MCU0)/trap_start.S
MCU0_MARCH := rv64i_zicsr
MCU0_PLUS := +need_irq=1
else ifneq ($(filter blink oled_%,$(APP)),)
MCU0_CRT := $(MCU0)/start.S
MCU0_MARCH := rv64i
MCU0_PLUS :=
else
MCU0_CRT := $(MCU0)/$(if $(filter tasks,$(APP)),task_start.S,trap_start.S)
MCU0_MARCH := rv64i_zicsr
MCU0_PLUS := +need_irq=1
endif
# a context switch costs several hundred cycles, so the scheduler's slice (DELAY/16) needs a longer DELAY in simulation
MCU0_DELAY ?= $(if $(filter tasks,$(APP)),40000,4000)
# oled_* apps live in teaching/oled (the Pmod OLEDrgb on JB, teaching/oled/README.md)
MCU0_SRC = $(if $(filter oled_%,$(APP)),$(TEACH)/oled,$(MCU0))/$(APP).c
MCU0_CC = $(CC) -march=$(MCU0_MARCH) -mabi=lp64 -mcmodel=medany -O2 -ffreestanding -fno-pie -nostdlib -nostartfiles -static -I $(TEACH)/oled \
    -Wl,--no-relax -Wl,--no-warn-rwx-segments -T $(ROOT)/software/probes/link.ld
MS := $(OUT)/mcu0/$(APP)
mcu0-sim:
	@echo "== mcu0-sim: $(APP) firmware on mcu_top (CORE=$(CORE), DELAY=$(MCU0_DELAY) ticks)"
	@mkdir -p $(MS)
	@$(MCU0_CC) -DDELAY=$(MCU0_DELAY) -o $(MS)/$(APP).elf $(MCU0_CRT) $(MCU0_SRC)
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(MS)/$(APP).elf $(MS)/$(APP).hex $(MS)/$(APP).tohost >/dev/null
	@[ "$(APP)" != blink ] || $(TOOLPREFIX)objdump -d $(MS)/$(APP).elf | grep -cE '\s(mul|div|rem|csr)' | grep -qx 0 \
	    || { echo "blink.elf uses M or CSR instructions"; exit 1; }
	@iverilog -g2005 -I $(ROOT)/rtl/cpu -I $(CORE) -o $(MS)/sim.vvp \
	    $(MCU0)/tb_mcu.v $(MCU0)/mcu_top.v $(MCU0)/mcu_router.v $(MCU0)/mcu_ram.v $(MCU0)/mcu_clint.v $(MCU0)/mcu_gpio.v $(MCU0_SPI) $(CORE)/*.v
	@vvp -n $(MS)/sim.vvp +hex=$(MS)/$(APP).hex +delay=$(MCU0_DELAY) $(MCU0_PLUS) $${VCD:+ +vcd=$(MS)/sim.vcd} > $(MS)/sim.log 2>&1; \
	    grep -E '^(LED|BTN|BUS|TRAP|SUMMARY|RESULT)' $(MS)/sim.log
	@grep -q '^RESULT PASS' $(MS)/sim.log

# ---- teaching/oled: the Pmod OLEDrgb on MCU-0. oled-sim runs an oled_* app (default oled_hello) against a model of
# the display that checks the power order, the SPI timing and the commands, and writes the screen to screen.png.
# The firmware's waits are scaled (1 ms = OLED_SIM_MS clocks); the SPI itself runs at full simulated speed. The timed
# frame push is 8 rows instead of 64 (FRAME_SHIFT=3, the time is scaled up). OLED_FAST=1: the unrolled spi_byte.
OAPP = $(if $(filter oled_%,$(APP)),$(APP),oled_hello)
OLED_SIM_MS ?= 40
OLED_FAST ?=
OLED_DEFS = $(if $(OLED_FAST),-DOLED_FAST)
# the SPI master (project 3); MCU0_SPI=work/mcu_spi.v tries your own
MCU0_SPI ?= $(MCU0)/mcu_spi.v
# testbench options per app (before the defaults: the first +option on the line wins): oled_spi draws no rectangles, and SW0 = 1 animates through the SPI master
OLED_TB_oled_spi = +rects=0 +sw=1
# snake: no frame push; steer by the script in oled/snake.script (LEFT at move 3 must be ignored: it is straight back;
# UP at move 8), end at game over with score 1 (LED3..1 = 101); mid.ppm is the screen after 11 moves
OLED_TB_oled_snake = +frame_bytes=0 +script=$(TEACH)/oled/snake.script +until_led3=1 +expect_led=5 \
    +snap=11 +snap_ppm=$(OS)/mid.ppm
# firmware defines per app in simulation: snake's tick is 4 s of scaled time (160,000 clocks), so that a move with
# a score redraw fits in one tick
OLED_SIMDEFS_oled_snake = -DTICK_MS=4000
OS = $(OUT)/oled/$(OAPP)
oled-sim:
	@echo "== oled-sim: $(OAPP) on mcu_top + SSD1331 model (CORE=$(CORE); waits scaled to 1 ms = $(OLED_SIM_MS) cycles)"
	@mkdir -p $(OS)
	@$(MAKE) -s --no-print-directory APP=$(OAPP) oled-fw-sim
	@iverilog -g2005 -I $(ROOT)/rtl/cpu -I $(CORE) -o $(OS)/sim.vvp $(TEACH)/oled/tb_oled.v $(TEACH)/oled/ssd1331_model.v \
	    $(MCU0)/mcu_top.v $(MCU0)/mcu_router.v $(MCU0)/mcu_ram.v $(MCU0)/mcu_clint.v $(MCU0)/mcu_gpio.v $(MCU0_SPI) $(CORE)/*.v
	@vvp -n $(OS)/sim.vvp +hex=$(OS)/$(OAPP).hex +ms=$(OLED_SIM_MS) $(OLED_TB_$(OAPP)) +frame_bytes=1536 +ppm=$(OS)/screen.ppm $${VCD:+ +vcd=$(OS)/sim.vcd} \
	    > $(OS)/sim.log 2>&1; grep -E '^(OLED|LED3|BTN|BUS|TRAP|SUMMARY|RESULT)' $(OS)/sim.log
	@python3 $(TEACH)/tools/ppm2png.py $(OS)/screen.ppm $(OS)/screen.png 4 && echo "screen: $(OS)/screen.png"
	@grep -q '^RESULT PASS' $(OS)/sim.log
oled-fw-sim:
	@$(MCU0_CC) $(OLED_DEFS) $(OLED_SIMDEFS_$(OAPP)) -DTICKS_PER_MS=$(OLED_SIM_MS) -DFRAME_SHIFT=3 -DDELAY=20000 -o $(OS)/$(OAPP).elf $(MCU0_CRT) $(MCU0_SRC)
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(OS)/$(OAPP).elf $(OS)/$(OAPP).hex $(OS)/$(OAPP).tohost >/dev/null
	@$(TOOLPREFIX)objdump -d $(OS)/$(OAPP).elf | grep -cE '\s(mul|div|rem$(if $(filter $(OLED_IRQ_APPS),$(OAPP)),,|csr))' | grep -qx 0 \
	    || { echo "$(OAPP).elf uses instructions its core cannot run (M; or CSRs in a step-2 app)"; exit 1; }

# board firmware (DELAY for 40 MHz) and the Vivado build: teaching/mcu0/build/ for blink, build-$(APP)/ otherwise
MCU0_BOARD_DELAY ?= 20000000
MCU0_BUILD := $(MCU0)/build$(if $(filter blink,$(APP)),,-$(APP))
# extra mcu_board parameters per app: the snake needs BTN3, so SW1 becomes the reset
MCU0_GENERIC_oled_snake = RESET_SW1=1
mcu0-fw:
	@mkdir -p $(MCU0_BUILD)
	@$(MCU0_CC) $(OLED_DEFS) -DDELAY=$(MCU0_BOARD_DELAY) -o $(MCU0_BUILD)/$(APP).elf $(MCU0_CRT) $(MCU0_SRC)
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(MCU0_BUILD)/$(APP).elf $(MCU0_BUILD)/$(APP).hex $(MCU0_BUILD)/$(APP).tohost
	@echo "firmware: $(MCU0_BUILD)/$(APP).hex (DELAY=$(MCU0_BOARD_DELAY))"
mcu0-bit: mcu0-fw
	@echo "== mcu0-bit: Vivado batch build (CORE=$(CORE), APP=$(APP)) -> $(MCU0_BUILD)/mcu_board.bit"
	cd $(MCU0_BUILD) && vivado -mode batch -nojournal -log vivado.log -source $(MCU0)/build.tcl \
	    -tclargs $(abspath $(CORE)) $(MCU0_BUILD)/$(APP).hex $(MCU0_BUILD) $(MCU0_GENERIC_$(APP))
	@grep -E 'WNS|Design Timing Summary' -A6 $(MCU0_BUILD)/timing.rpt | head -12

# program the PL over JTAG (hardware manager; the PS is left alone). BIT= picks another bitstream.
BIT ?= $(MCU0_BUILD)/mcu_board.bit
mcu0-prog:
	@echo "== mcu0-prog: $(BIT)"
	cd $(MCU0_BUILD) && vivado -mode batch -nojournal -log program.log -source $(MCU0)/program.tcl -tclargs $(BIT) | grep -E 'PROGRAMMED|ERROR|no xc7z020|no such'

clean:
	rm -rf $(OUT)
