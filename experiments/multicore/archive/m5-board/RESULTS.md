# MC-M5 RESULTS (2026-09-27, board PYNQ-Z1, cold boots a534c757… (dual) and 4e3f038a… (restore))

| item | value |
|---|---|
| dual payload programmed / re-hashed on board | 43e5b414c093f27854513f6ae08addbb431c6865b85f822685a824cda66e2841 |
| dual gates | 6/6: BOOT, CLINT, LOCK (20000/20000/20000, SC fails 0x111f/0x1387), PBUS, FENCEI, LONG (100000 iters/hart, equal sums) |
| dual xv6 (m4smoke, attempt 3) | PASS: banner 5.4 s, prompt 11.7 s, b0compute 13.9 s, m3par2 15.9 s, m3fs 22.1 s; host exit 0, deliberate stop |
| dual xv6 attempts | 1: refused pre-launch (no /var/lock); 2: kernel + workload correct, pattern CRLF mismatch (host stopped cleanly); 3: PASS |
| restore payload programmed / re-hashed on board | 79a114aed6ab089514210dc182e7595a57d795851b3a3ed4715d41819bef92c1 (user's cache config) |
| restore gates / perf | 8/8; perf02/03/04/06 3/3 usable each |
| production trees modified | none (ips-cache : only board-metrics.json, modified 2026-09-25 before this session) |
| performance measured | none (not in scope); dual sim of this workload: 2175 s host wall vs 22 s on the board |
