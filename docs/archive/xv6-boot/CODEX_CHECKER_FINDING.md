# Command acceptance false positive — 2026-09-20

Independent counterexample: `/tmp/xv6-check-review-PTtPNG/console.txt` contains a kernel banner, five prompts, echo output, a directory entry `README 2 2 2441`, a README sentence, and `echo abc | wc` with NO output. No stages.txt exists. Running `check-xv6.py <dir> --require-commands` returned exit 0: `XV6_CHECK stages=0 prompts=5 console_bytes=165 fails=0`.

The pipe regex matches the directory entry from an earlier command. Missing stage records are silently accepted. Thus the statement that the checker was already immune to command confusion is too broad. This does not negate observed shell startup, echo or directory output; it blocks final four-command acceptance.

Fix within the current task: independently bind each command to its own prompt/echo/output/return boundary, require the ordered complete stage set and final stop/actual process status records, and reject missing pipe output despite earlier ls numbers. Preserve console line boundaries and drain stdout on process exit; the current pump returns as soon as poll() notices termination, risking dropped trailing evidence. Do not rewrite active run files. Use immutable new evidence and genuine passing-run mutations when available.
