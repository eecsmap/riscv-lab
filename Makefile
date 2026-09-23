.PHONY: check board-project xv6 bench-selftest bench-metrics bench-check bench-profile-cli e1-rehearsal
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
	python3 benchmarks/tools/e1_model_selftest.py
	python3 benchmarks/tools/check_e1_prediction_selftest.py
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
# The E1 hardware procedure, rehearsed offline against a scripted fake. Opens no device.
e1-rehearsal:
	bash experiments/E1-clock-scaling/scripts/rehearsal.sh
	bash experiments/E1-clock-scaling/scripts/entrypoint-rehearsal.sh

bench-profile-cli:
	bash benchmarks/workload-profiles/cli_selftest.sh $(or $(OUT),/tmp/b0-profile-cli)
