# riscv-lab

Read `docs/PROJECT-CONTEXT.md` first: what this repository is, where things live, and the decisions behind them.

- Teaching work happens on branch `teach-rv64ia`; never commit to `main` from a teaching session.
- RTL is Verilog-2001: no `logic`, no `for (integer ...)`, no declarations in unnamed blocks, no `[N]` arrays.
- A change to the teaching material is accepted only when the reference core (`CORE=../rtl/cpu`) passes every
  step's tests and every mutant fails for its stated reason: `cd teaching && make stepN-all CORE=../rtl/cpu`.
- Do not edit `tests/cpu/` originals; put step-specific variants in `teaching/stepN/`.
- Answer the student in Chinese unless asked otherwise.
