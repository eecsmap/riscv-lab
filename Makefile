.PHONY: check board-project xv6 bench-selftest bench-metrics bench-check bench-profile-cli
check:
	python3 tools/check.py
board-project:
	python3 tools/prepare-board.py
xv6:
	$(MAKE) -B -C software/xv6 kernel/kernel fs.img CPPFLAGS=-DTEACHING_SIM_MEM_MIB=128 $(if $(TOOLPREFIX),TOOLPREFIX=$(TOOLPREFIX),)

# --- B0 performance baseline (additive; existing targets above are unchanged) ---
bench-selftest:
	python3 benchmarks/tools/selftest.py
	python3 benchmarks/workload-profiles/profile_selftest.py
bench-metrics:
	@for d in experiments/B0-measurement/runs/*/; do \
	  python3 benchmarks/tools/gen_metrics.py "$$d"; \
	done
	python3 benchmarks/tools/gen_comparisons.py
bench-check: bench-selftest
	@for d in experiments/B0-measurement/runs/*/; do \
	  python3 benchmarks/tools/gen_metrics.py "$$d" >/dev/null; \
	done
	python3 benchmarks/tools/gen_comparisons.py --check
	python3 benchmarks/tools/gen_baseline_table.py --check
	python3 benchmarks/tools/verify_identities.py
bench-profile-cli:
	bash benchmarks/workload-profiles/cli_selftest.sh $(or $(OUT),/tmp/b0-profile-cli)
