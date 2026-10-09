# Teaching steps: `make stepN` runs step N's tests against the core in $(CORE); `make stepN-mutants` runs the
# fault injections that step N's tests must catch; `make stepN-all` is both.
#
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

.PHONY: all clean step1 step1-mutants step1-all

all: step1-all

# ---- step 1: the first instructions retire (addi, auipc, sd, jal; 4-byte aligned fetch) --------------------
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

clean:
	rm -rf $(OUT)
