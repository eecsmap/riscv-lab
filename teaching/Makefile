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

.PHONY: all clean step1-init step1 step1-mutants step1-all step2 step2-mutants step2-all step3 step3-mutants step3-all pl-sim mcu0-sim mcu0-fw mcu0-bit

all: step1-all

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

# ---- MCU-0: core + router + RAM + CLINT + GPIO, blink firmware in C (teaching/mcu0/README.md) -----------------
MCU0 := $(TEACH)/mcu0
MCU0_DELAY ?= 4000
mcu0-sim:
	@echo "== mcu0-sim: blink firmware on mcu_top (CORE=$(CORE), DELAY=$(MCU0_DELAY) ticks)"
	@mkdir -p $(OUT)/mcu0
	@$(CC) -march=rv64i -mabi=lp64 -O2 -ffreestanding -fno-pie -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--no-warn-rwx-segments \
	    -DDELAY=$(MCU0_DELAY) -T $(ROOT)/software/probes/link.ld -o $(OUT)/mcu0/blink.elf $(MCU0)/start.S $(MCU0)/blink.c
	@$(OBJCOPY) -O binary $(OUT)/mcu0/blink.elf $(OUT)/mcu0/blink.bin
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(OUT)/mcu0/blink.elf $(OUT)/mcu0/blink.hex $(OUT)/mcu0/blink.tohost >/dev/null
	@$(TOOLPREFIX)objdump -d $(OUT)/mcu0/blink.elf | grep -cE '\s(mul|div|rem|csr)' | grep -qx 0 || { echo "blink.elf uses M or CSR instructions"; exit 1; }
	@iverilog -g2005 -I $(ROOT)/rtl/cpu -I $(CORE) -o $(OUT)/mcu0/sim.vvp \
	    $(MCU0)/tb_mcu.v $(MCU0)/mcu_top.v $(MCU0)/mcu_router.v $(MCU0)/mcu_ram.v $(MCU0)/mcu_clint.v $(MCU0)/mcu_gpio.v $(CORE)/*.v
	@vvp -n $(OUT)/mcu0/sim.vvp +hex=$(OUT)/mcu0/blink.hex +delay=$(MCU0_DELAY) $${VCD:+ +vcd=$(OUT)/mcu0/sim.vcd} > $(OUT)/mcu0/sim.log 2>&1; \
	    grep -E '^(LED|BTN|BUS|SUMMARY|RESULT)' $(OUT)/mcu0/sim.log
	@grep -q '^RESULT PASS' $(OUT)/mcu0/sim.log

# board firmware (DELAY for 40 MHz) and the Vivado build; the bitstream lands in teaching/mcu0/build/
MCU0_BOARD_DELAY ?= 20000000
MCU0_BUILD := $(MCU0)/build
mcu0-fw:
	@mkdir -p $(MCU0_BUILD)
	@$(CC) -march=rv64i -mabi=lp64 -O2 -ffreestanding -fno-pie -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--no-warn-rwx-segments \
	    -DDELAY=$(MCU0_BOARD_DELAY) -T $(ROOT)/software/probes/link.ld -o $(MCU0_BUILD)/blink.elf $(MCU0)/start.S $(MCU0)/blink.c
	@python3 $(TEACH)/tools/elf2hex.py $(OBJCOPY) $(NM) $(MCU0_BUILD)/blink.elf $(MCU0_BUILD)/blink.hex $(MCU0_BUILD)/blink.tohost
	@echo "firmware: $(MCU0_BUILD)/blink.hex (DELAY=$(MCU0_BOARD_DELAY))"
mcu0-bit: mcu0-fw
	@echo "== mcu0-bit: Vivado batch build (CORE=$(CORE)) -> $(MCU0_BUILD)/mcu_board.bit"
	cd $(MCU0_BUILD) && vivado -mode batch -nojournal -log vivado.log -source $(MCU0)/build.tcl \
	    -tclargs $(abspath $(CORE)) $(MCU0_BUILD)/blink.hex $(MCU0_BUILD)
	@grep -E 'WNS|Design Timing Summary' -A6 $(MCU0_BUILD)/timing.rpt | head -12

clean:
	rm -rf $(OUT)
