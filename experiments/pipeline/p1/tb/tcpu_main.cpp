// M2-1: Verilator main for the standalone teaching-CPU harness.
//  - pre-loads the ELF's PT_LOAD segments into the memory model (this is NOT the real ROM boot path)
//  - watches the ELF's `tohost` symbol: (code << 1) | 1, code 0 = pass
//  - records the normal-retirement trace (commit_pc) and can compare an ROI window against a file
//  - fails loudly on a trap event, a protocol error, or a timeout; exit code is never 0 in those cases
#include "VTeachingTop.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <utility>
#include <cerrno>

static bool load_elf(const char* path, std::map<uint64_t,uint64_t>& words,
                     uint64_t& tohost_addr, uint64_t& entry, uint64_t& roi_sym) {
  FILE* f = fopen(path, "rb"); if (!f) return false;
  std::vector<uint8_t> b; uint8_t buf[65536]; size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
  fclose(f);
  if (b.size() < 64 || memcmp(b.data(), "\177ELF", 4) || b[4] != 2) return false;
  auto rd16=[&](size_t o){ return (uint16_t)(b[o] | (b[o+1]<<8)); };
  auto rd32=[&](size_t o){ uint32_t v=0; for(int i=0;i<4;i++) v |= (uint32_t)b[o+i]<<(8*i); return v; };
  auto rd64=[&](size_t o){ uint64_t v=0; for(int i=0;i<8;i++) v |= (uint64_t)b[o+i]<<(8*i); return v; };
  entry = rd64(24);
  uint64_t phoff = rd64(32), shoff = rd64(40);
  uint16_t phentsize = rd16(54), phnum = rd16(56);
  uint16_t shentsize = rd16(58), shnum = rd16(60), shstrndx = rd16(62);
  for (int i = 0; i < phnum; i++) {
    size_t p = phoff + (size_t)i * phentsize;
    if (rd32(p) != 1) continue;                       // PT_LOAD
    uint64_t off = rd64(p+8), vaddr = rd64(p+16), filesz = rd64(p+32), memsz = rd64(p+40);
    for (uint64_t a = 0; a < memsz; a++) {
      uint64_t addr = vaddr + a;
      uint8_t v = (a < filesz) ? b[off + a] : 0;
      uint64_t w = addr & ~7ULL; int lane = addr & 7;
      words[w] = (words[w] & ~(0xffULL << (lane*8))) | ((uint64_t)v << (lane*8));
    }
  }
  tohost_addr = 0; roi_sym = 0;
  for (int i = 0; i < shnum; i++) {                   // find .symtab / .strtab
    size_t s = shoff + (size_t)i * shentsize;
    if (rd32(s+4) != 2) continue;                     // SHT_SYMTAB
    uint64_t soff = rd64(s+24), ssize = rd64(s+32), link = rd32(s+40), esz = rd64(s+56);
    size_t stro = (size_t)rd64(shoff + link*shentsize + 24);
    for (uint64_t o = 0; o + esz <= ssize; o += esz) {
      uint32_t nameo = rd32(soff+o); uint64_t val = rd64(soff+o+8);
      const char* nm = (const char*)&b[stro + nameo];
      if (!strcmp(nm, "tohost")) tohost_addr = val;
      if (!strcmp(nm, "roi_measured")) roi_sym = val;
    }
  }
  (void)shstrndx;
  return tohost_addr != 0;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  static const char* stn[] = {"IF_REQ","IF_WAIT","EXEC","MEM_REQ","MEM_WAIT","WB","TRAP","HALT","ARCH","MUL","IF2_REQ","IF2_WAIT","XLATE"};
  const char* elf = nullptr; const char* tracefile = nullptr; const char* roifile = nullptr;
  const char* commitfile = nullptr;
  const char* memdumpfile = nullptr; uint64_t memdump_addr = 0, memdump_n = 0;   // CPU-A
  unsigned exp_reg = 0; unsigned long long exp_reg_val = 0; bool have_exp_reg = false;
  long max_cycles = 2000000; uint64_t roi_start = 0, roi_end = 0;
  long expect_trap = 0, expect_data_req = 0; bool have_expect_trap = false, have_expect_dreq = false;
  int expect_exit = -1;
  uint64_t dreq_at_trap = 0;
  bool stop_at_trap = false;
  long max_traps = 64, expect_traps = -1, expect_cause = -1, expect_ints = -1, min_irq_hits = -1;
  long exp_watch_req = 0, exp_watch_wreq = 0, exp_watch_resp = 0, exp_watch_write = 0; bool have_exp_watch = false;
  const char* exp_fire_state = nullptr;
  uint64_t target_pc = 0, inject_pc = 0, target_addr = 0, target_reg_val = 0; unsigned target_reg = 0;
  bool have_target = false, have_target_addr = false, have_target_reg = false;
  int exp_fire_write = -1; long exp_apply_events = -1;
  // the ordered chain for the named target instruction, all sampled while the run happens
  uint64_t tgt_req_cycle = 0, tgt_resp_cycle = 0, tgt_commit_cycle = 0;
  uint64_t tgt_retired_at_irq = 0, first_irq_cycle = 0, tgt_reg_at_irq = 0;
  bool tgt_reg_sampled = false;
  uint64_t prev_watch_req = 0, prev_watch_resp = 0;
  std::vector<std::pair<unsigned,uint64_t>> expect_csr;
  std::vector<std::pair<uint64_t,uint64_t>> expect_commit;
  std::map<uint64_t,uint64_t> pc_count;   // how often each PC retired: used to prove a faulting PC never did

  // ---- strict option parsing ------------------------------------------------
  // A mistyped switch used to be ignored, so a run could "pass" with the check it named never executed.
  // Every option is now on an explicit whitelist, every value is fully consumed, and anything unrecognised,
  // malformed, out of range, empty, unreadable or unwritable stops the run before the first cycle.
  int argerr = 0;
  auto bad = [&](const std::string& why) { fprintf(stderr, "argument error: %s\n", why.c_str()); argerr = 1; };
  auto parse_long = [&](const char* v, const char* name, long lo, long hi) -> long {
    if (!*v) { bad(std::string(name) + " needs a value"); return lo; }
    errno = 0; char* end = nullptr; long x = strtol(v, &end, 0);
    if (errno == ERANGE) { bad(std::string(name) + ": value out of range"); return lo; }
    if (end == v || *end) { bad(std::string(name) + ": '" + v + "' is not a number"); return lo; }
    if (x < lo || x > hi) { bad(std::string(name) + ": " + v + " is outside [" + std::to_string(lo) + "," + std::to_string(hi) + "]"); return lo; }
    return x;
  };
  auto parse_u64hex = [&](const char* v, const char* name, uint64_t* out) {
    if (!*v) { bad(std::string(name) + " needs a value"); return; }
    errno = 0; char* end = nullptr; unsigned long long x = strtoull(v, &end, 16);
    if (errno == ERANGE) { bad(std::string(name) + ": value out of range"); return; }
    if (end == v || *end) { bad(std::string(name) + ": '" + v + "' is not a hexadecimal number"); return; }
    *out = x;
  };
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a.rfind("+verilator+", 0) == 0) continue;            // handled by Verilated::commandArgs
    if (a.empty() || a[0] != '+') { bad("'" + a + "' is not an option (options start with '+')"); continue; }
    size_t eq = a.find('=');
    std::string key = (eq == std::string::npos) ? a : a.substr(0, eq);
    const char* val = (eq == std::string::npos) ? "" : argv[i] + eq + 1;
    bool needs_value = (eq != std::string::npos);
    if      (key == "+elf")             { if (!needs_value || !*val) bad("+elf needs a file"); else elf = val; }
    else if (key == "+max-cycles")      max_cycles = parse_long(val, "+max-cycles", 1, 1000000000L);
    else if (key == "+max-traps")       max_traps  = parse_long(val, "+max-traps", 0, 1000000L);
    // PIPE-P1: read by the harness itself ($test$plusargs / $value$plusargs); accepted here, validated there
    else if (key == "+pipe-trace")      { if (*val) bad("+pipe-trace takes no value"); }
    else if (key == "+pipe-debug")      { if (*val) bad("+pipe-debug takes no value"); }
    else if (key == "+irq-at-retire")   { parse_long(val, "+irq-at-retire", 1, 1000000000L); }
    else if (key == "+trace-out")       { if (!*val) bad("+trace-out needs a file"); else tracefile = val; }
    else if (key == "+commit-trace")    { if (!*val) bad("+commit-trace needs a file"); else commitfile = val; }
    // CPU-A: dump N 64-bit words of the model's memory at the end, so a checker can compare the real
    // memory image against one it computed itself. Read-only; it changes nothing in the run.
    else if (key == "+mem-dump") {
      std::string v = val; size_t c1 = v.find(':'), c2 = v.rfind(':');
      if (c1 == std::string::npos || c2 == c1) bad("+mem-dump needs addr:count:file");
      else { parse_u64hex(v.substr(0, c1).c_str(), "+mem-dump addr", &memdump_addr);
             memdump_n = (uint64_t)parse_long(v.substr(c1 + 1, c2 - c1 - 1).c_str(), "+mem-dump count", 1, 65536);
             memdumpfile = strdup(v.substr(c2 + 1).c_str()); }
    }
    else if (key == "+roi-expect")      { if (!*val) bad("+roi-expect needs a file"); else roifile = val; }
    else if (key == "+roi") {
      std::string v = val; size_t c = v.find(':');
      if (c == std::string::npos) bad("+roi needs start:end");
      else { parse_u64hex(v.substr(0, c).c_str(), "+roi start", &roi_start);
             parse_u64hex(v.substr(c + 1).c_str(), "+roi end", &roi_end); }
    }
    else if (key == "+expect-trap")     { expect_trap = parse_long(val, "+expect-trap", 0, 63); have_expect_trap = true; stop_at_trap = true; }
    else if (key == "+expect-data-req") { expect_data_req = parse_long(val, "+expect-data-req", 0, 1000000L); have_expect_dreq = true; }
    else if (key == "+expect-exit")     expect_exit  = (int)parse_long(val, "+expect-exit", 0, 255);
    else if (key == "+expect-traps")    expect_traps = parse_long(val, "+expect-traps", 0, 1000000L);
    else if (key == "+expect-interrupts") expect_ints = parse_long(val, "+expect-interrupts", 0, 1000000L);
    else if (key == "+min-irq-hits")    min_irq_hits = parse_long(val, "+min-irq-hits", 0, 1000000000L);
    else if (key == "+expect-fire-state") { exp_fire_state = val; }
    else if (key == "+target-pc")  { parse_u64hex(val, "+target-pc", &target_pc); have_target = true; }
    else if (key == "+inject-pc")  { parse_u64hex(val, "+inject-pc", &inject_pc); }
    else if (key == "+target-addr"){ parse_u64hex(val, "+target-addr", &target_addr); have_target_addr = true; }
    else if (key == "+expect-fire-write") { exp_fire_write = (int)parse_long(val, "+expect-fire-write", 0, 1); }
    else if (key == "+target-reg") {
      std::string v = val; size_t c = v.find(':');
      if (c == std::string::npos) { bad("+target-reg needs <reg>:<hexvalue>"); continue; }
      target_reg = (unsigned)parse_long(v.substr(0, c).c_str(), "+target-reg register", 0, 31);
      parse_u64hex(v.substr(c + 1).c_str(), "+target-reg value", &target_reg_val);
      have_target_reg = true;
    }
    else if (key == "+expect-apply-events") exp_apply_events = parse_long(val, "+expect-apply-events", 0, 1000000L);
    else if (key == "+expect-watch") {
      // <requests>:<write requests>:<applied writes> at the watched address, all exact
      std::string v = val; std::vector<std::string> f; size_t p0 = 0, p1;
      while ((p1 = v.find(':', p0)) != std::string::npos) { f.push_back(v.substr(p0, p1 - p0)); p0 = p1 + 1; }
      f.push_back(v.substr(p0));
      if (f.size() != 4) { bad("+expect-watch needs <req>:<wreq>:<resp>:<writes>"); continue; }
      exp_watch_req   = parse_long(f[0].c_str(), "+expect-watch req", 0, 1000000L);
      exp_watch_wreq  = parse_long(f[1].c_str(), "+expect-watch wreq", 0, 1000000L);
      exp_watch_resp  = parse_long(f[2].c_str(), "+expect-watch resp", 0, 1000000L);
      exp_watch_write = parse_long(f[3].c_str(), "+expect-watch writes", 0, 1000000L);
      have_exp_watch = true;
    }
    else if (key == "+expect-cause")    expect_cause = parse_long(val, "+expect-cause", 0, 63);
    else if (key == "+stop-at-trap")    { if (needs_value) bad("+stop-at-trap takes no value"); stop_at_trap = true; }
    else if (key == "+expect-reg") {
      std::string v = val; size_t c = v.find(':');
      if (c == std::string::npos) { bad("+expect-reg needs <reg>:<hexvalue>"); continue; }
      long r = parse_long(v.substr(0, c).c_str(), "+expect-reg register", 0, 31);
      uint64_t x = 0; parse_u64hex(v.substr(c + 1).c_str(), "+expect-reg value", &x);
      exp_reg = (unsigned)r; exp_reg_val = x; have_exp_reg = true;
    }
    else if (key == "+expect-commit-count") {
      // <hex pc>:<count> -- how often that PC may retire. This is how "an instruction did not retire" is
      // established from outside the program, since a program cannot observe its own non-retirement.
      std::string v = val; size_t c = v.find(':');
      if (c == std::string::npos) { bad("+expect-commit-count needs <hexpc>:<count>"); continue; }
      uint64_t pc = 0; parse_u64hex(v.substr(0, c).c_str(), "+expect-commit-count pc", &pc);
      long n = parse_long(v.substr(c + 1).c_str(), "+expect-commit-count count", 0, 1000000L);
      expect_commit.push_back({pc, (uint64_t)n});
    }
    else if (key == "+expect-csr") {
      // <sel>:<hexvalue>; sel indexes the CSR read-back port, not a CSR address
      std::string v = val; size_t c = v.find(':');
      if (c == std::string::npos) { bad("+expect-csr needs <sel>:<hexvalue>"); continue; }
      long sel = parse_long(v.substr(0, c).c_str(), "+expect-csr selector", 0, 24);   // CPU-SU: 0..24, see names[]
      uint64_t x = 0; parse_u64hex(v.substr(c + 1).c_str(), "+expect-csr value", &x);
      expect_csr.push_back({(unsigned)sel, x});
    }
    else if (key == "+core-reset-at-op" || key == "+core-reset-n") { /* CPU-M closeout: parsed below */ }
    else bad("unknown option '" + key + "'");
  }
  if (!elf) bad("+elf=<file> is required");
  // fail before the first cycle if an input cannot be read or an output cannot be written
  auto check_readable = [&](const char* f, const char* what) {
    if (!f) return; FILE* t = fopen(f, "rb");
    if (!t) bad(std::string(what) + ": cannot read '" + f + "'"); else fclose(t);
  };
  auto check_writable = [&](const char* f, const char* what) {
    if (!f) return; FILE* t = fopen(f, "w");
    if (!t) bad(std::string(what) + ": cannot write '" + f + "'"); else fclose(t);
  };
  check_readable(elf, "+elf"); check_readable(roifile, "+roi-expect");
  check_writable(tracefile, "+trace-out"); check_writable(commitfile, "+commit-trace");
  if (roifile && !roi_end) bad("+roi-expect without +roi=start:end would compare an empty window");
  if (argerr) { fprintf(stderr, "usage: tcpu_tb +elf=<file> [+max-cycles=N] [+max-traps=N] [+stop-at-trap]\n"
                                "       [+trace-out=f] [+commit-trace=f] [+roi=start:end] [+roi-expect=f]\n"
                                "       [+expect-trap=N] [+expect-traps=N] [+expect-cause=N] [+expect-data-req=N]\n"
                                "       [+expect-exit=N] [+expect-reg=R:HEX] [+expect-csr=SEL:HEX]\n"
                                "       [+expect-commit-count=HEXPC:N] [+expect-interrupts=N] [+min-irq-hits=N]\n"
                                "       [+expect-watch=REQ:WREQ:RESP:WRITES] [+expect-fire-state=NAME]\n"
                                "       [+target-pc=HEX] [+inject-pc=HEX] [+target-addr=HEX] [+target-reg=R:HEX]\n"
                                "       [+expect-fire-write=0|1] [+expect-apply-events=N]\n"); return 3; }

  std::map<uint64_t,uint64_t> words; uint64_t tohost_addr=0, entry=0, roi_sym=0;
  if (!load_elf(elf, words, tohost_addr, entry, roi_sym)) { fprintf(stderr, "ELF load failed (no tohost?)\n"); return 3; }

  VTeachingTop* top = new VTeachingTop;
  top->rst = 1; top->clk = 0;
  for (int i = 0; i < 8; i++) { top->clk = !top->clk; top->eval(); }
  // pre-load memory through the harness' backdoor port
  for (auto& kv : words) {
    uint64_t off = kv.first - 0x80000000ULL;
    if (off >= (uint64_t)(1<<16)*8) continue;
    top->bd_we = 1; top->bd_addr = off >> 3; top->bd_data = kv.second;
    top->clk = 1; top->eval(); top->clk = 0; top->eval();
  }
  top->bd_we = 0;
  top->bd_rd_addr   = (tohost_addr - 0x80000000ULL) >> 3;   // held for the whole run
  top->bd_fault_addr = (uint32_t)tohost_addr;                // target for the completion controls
  top->bd_watch_addr = (uint32_t)target_addr;                // 0 unless +target-addr was given
  top->bd_inject_pc  = inject_pc;                            // 0 unless +inject-pc was given
  top->rst = 0;
  top->eval();

  // ---- CPU-M closeout: a core reset applied while a multiply or a divide is in progress ------------
  //   +core-reset-at-op=mul|div   which family of long operation to interrupt
  //   +core-reset-n=<k>           on the k-th cycle the core is in S_MUL for that family (default 3)
  // The reset covers the core and the unit only (bd_core_rst); the memory model keeps its contents and
  // counters. What is then required: no commit of the interrupted instruction, the first commit after the
  // reset is the reset vector, and the program then runs to its normal end.
  const char* crst_op = nullptr; long crst_n = 3; bool crst_done = false; long crst_hits = 0;
  uint64_t crst_pc = 0; uint32_t crst_insn = 0; long crst_cycle = 0; int crst_pulse = 0;
  bool crst_saw_reset_vector = false, crst_bad_commit = false; uint64_t crst_bad_pc = 0;
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+core-reset-at-op=", 18)) crst_op = argv[i] + 18;   // mul | div | if2 (CPU-C: mid-fetch)
    else if (!strncmp(argv[i], "+core-reset-n=", 14)) crst_n = atol(argv[i] + 14);
  }
  auto insn_at = [&](uint64_t pc) -> uint32_t {
    auto it = words.find(pc & ~7ULL); if (it == words.end()) return 0;
    return pc & 4 ? (uint32_t)(it->second >> 32) : (uint32_t)it->second; };
  auto is_family = [&](uint32_t insn, const char* fam) -> bool {
    uint32_t opc = insn & 0x7f, f3 = (insn >> 12) & 7, f7 = (insn >> 25) & 0x7f;
    if (f7 != 1 || (opc != 0x33 && opc != 0x3b)) return false;
    bool mul = (opc == 0x33) ? (f3 < 4) : (f3 == 0);
    return !strcmp(fam, "mul") ? mul : !mul; };
  top->bd_core_rst = 0;

  std::vector<uint64_t> trace;
  struct Commit { uint64_t pc; uint32_t insn; uint8_t rdv, rd; uint64_t val; uint8_t len; };
  std::vector<Commit> commits;
  bool in_roi = false;
  long cycles = 0; int rc = 2; uint64_t retired = 0;
  const long TAIL_GRACE = 200;          // generous: the longest response profile here is 8 cycles
  bool exit_pending = false; uint64_t exit_code_raw = 0, retired_at_tohost = 0; long tail_deadline = 0;
  uint64_t traps = 0, last_cause = 0, last_epc = 0, last_tval = 0, interrupts = 0;
  uint64_t first_irq_epc = 0; bool target_faulted = false;
  while (cycles < max_cycles) {
    top->clk = 1; top->eval();
    // the target's transactions, seen as they happen rather than counted up at the end
    if (have_target_addr) {
      if (top->watch_req > prev_watch_req) {
        prev_watch_req = top->watch_req;
        if (!tgt_req_cycle && top->fire_is_write == 0) { /* set below only for the target access */ }
      }
    }
    // the aimed core reset: decide on the state the core is in *now*, before this cycle's commit is read
    if (crst_op && !crst_done) {
      if (crst_pulse) { if (--crst_pulse == 0) { top->bd_core_rst = 0; crst_done = true; } }
      else if ((!strcmp(crst_op, "if2") && top->cpu_state_o == 11) ||
               (!strcmp(crst_op, "ptw") && top->cpu_state_o == 12) ||
               (strcmp(crst_op, "if2") && top->cpu_state_o == 9 && is_family(insn_at(top->cpu_pc_o), crst_op))) {
        if (++crst_hits == crst_n) {
          crst_pc = top->cpu_pc_o; crst_insn = insn_at(crst_pc); crst_cycle = cycles;
          top->bd_core_rst = 1; crst_pulse = 2;
          printf("CORE RESET cycle=%ld pc=0x%lx insn=0x%08x state=%s family=%s (hit %ld)\n",
                 cycles, (unsigned long)crst_pc, crst_insn, !strcmp(crst_op, "if2") ? "IF2_WAIT" : !strcmp(crst_op, "ptw") ? "XLATE" : "MUL", crst_op, crst_hits);
        }
      }
    }
    if (top->commit_valid) {
      retired++;
      uint64_t pc = top->commit_pc;
      if (crst_op && crst_cycle && !crst_saw_reset_vector) {
        // between the reset and the first commit at the reset vector, nothing may commit at all --
        // least of all the instruction that was interrupted
        if (pc == entry) crst_saw_reset_vector = true;
        else { crst_bad_commit = true; crst_bad_pc = pc; }
      }
      pc_count[pc]++;
      if (have_target && pc == target_pc && !tgt_commit_cycle) tgt_commit_cycle = (uint64_t)cycles;
      if (commitfile) commits.push_back({pc, (uint32_t)top->commit_insn, (uint8_t)top->commit_rd_valid,
                                         (uint8_t)top->commit_rd, (uint64_t)top->commit_rd_data,
                                         (uint8_t)top->commit_len});
      // ROI window is (start, end]: opened once the starting csrr has retired, closed including the ending csrr
      if (roi_end) {
        if (!in_roi) { if (pc == roi_start) in_roi = true; }
        else { trace.push_back(pc); if (pc == roi_end) in_roi = false; }
      }
    }
    if (top->trap_valid) {
      // A trap is an architectural event now, not the end of the run: the program's own handler deals with
      // it. Only a test that asks to stop at the first trap ends here, and it says so explicitly.
      traps++;
      last_cause = top->trap_cause; last_epc = top->trap_epc; last_tval = top->trap_tval;
      if (traps <= 8)
        printf("TRAP %s cause=%lu epc=0x%lx tval=0x%lx after %ld cycles\n",
               top->trap_interrupt ? "interrupt" : "exception",
               (unsigned long)(top->trap_cause & 0x7fffffffffffffffULL),
               (unsigned long)top->trap_epc, (unsigned long)top->trap_tval, cycles);
      if (top->trap_interrupt) {
        interrupts++;
        if (!first_irq_epc) {
          first_irq_epc = top->trap_epc;
          first_irq_cycle = (uint64_t)cycles;
          // sample, at this instant, how many times the named target has retired and what it wrote
          tgt_retired_at_irq = (have_target && pc_count.count(target_pc)) ? pc_count[target_pc] : 0;
          if (have_target_reg) { top->bd_reg_addr = target_reg; top->eval(); tgt_reg_at_irq = top->bd_reg_data; tgt_reg_sampled = true; }
        }
      }
      else if (top->irq_fires && top->trap_epc == top->fire_pc) target_faulted = true;
      else if (top->trap_cause >> 63) { printf("TRAP FLAG FAIL: cause has bit 63 but trap_interrupt is low\n"); rc = 18; break; }
      if (top->trap_interrupt && !(top->trap_cause >> 63)) { printf("TRAP FLAG FAIL: an interrupt without bit 63 in mcause\n"); rc = 18; break; }
      if (stop_at_trap) { dreq_at_trap = top->n_data_req; rc = 4; break; }
      if (traps > max_traps) {
        printf("TRAP STORM: %lu traps, the handler is not making progress\n", (unsigned long)traps);
        rc = 13; break;
      }
    }
    top->clk = 0; top->eval();
    cycles++;
    // Completion. The backdoor sees the tohost word the moment the memory model accepts the write, which is
    // before the response and before the store retires. Stopping there would count an unfinished transaction
    // as a finished one, so the value is latched and the run continues until that store has been answered and
    // has retired. A tail that never completes is a failure with its own code, not a pass.
    uint64_t th = top->bd_rd_data;   // tohost poll (backdoor, address held above)
    if ((th & 1) && !exit_pending) {
      exit_pending = true; exit_code_raw = th >> 1;
      retired_at_tohost = retired; tail_deadline = cycles + TAIL_GRACE;
      printf("TOHOST value observed in memory at cycle %ld, waiting for the store to complete and retire\n", cycles);
    }
    if (exit_pending) {
      bool answered = (top->n_req == top->n_resp);
      bool retired_store = (retired > retired_at_tohost);
      if (answered && retired_store) {
        uint64_t code = exit_code_raw;
        printf("TOHOST code=%lu after %ld cycles, retired=%lu (store answered and retired)\n",
               (unsigned long)code, cycles, (unsigned long)retired);
        rc = (code == 0) ? 0 : (int)(code > 250 ? 250 : code);
        break;
      }
      if (cycles > tail_deadline) {
        printf("TAIL INCOMPLETE after %ld cycles: req=%lu resp=%lu, retired %lu of the store\n", cycles,
               (unsigned long)top->n_req, (unsigned long)top->n_resp, (unsigned long)(retired - retired_at_tohost));
        rc = 10; break;
      }
    }
  }
  if (rc == 2 && cycles >= max_cycles) printf("TIMEOUT after %ld cycles, retired=%lu\n", cycles, (unsigned long)retired);
  // rc 2 is the generic timeout; any specific finding below is more informative and replaces it
  printf("PRIV at exit=%d\n", (int)top->cpu_priv_o);
  if (top->proto_errors) { printf("PROTOCOL ERRORS=%lu\n", (unsigned long)top->proto_errors); if (rc == 0 || rc == 2) rc = 5; }
  if (top->obs_errors) { printf("OBSERVATION ERRORS=%lu\n", (unsigned long)top->obs_errors); if (rc == 0 || rc == 2) rc = 11; }
  printf("IRQ hits=%lu fires=%lu clears=%lu\n", (unsigned long)top->irq_hits,
         (unsigned long)top->irq_fires, (unsigned long)top->irq_clears);

  if (top->irq_fires)
    printf("FIRE cycle=%lu pc=0x%lx state=%s enabled=%d req_valid=%d req_ready=%d outstanding=%d priv=%d\n",
           (unsigned long)top->fire_cycle, (unsigned long)top->fire_pc,
           top->fire_state < 13 ? stn[top->fire_state] : "?", (int)top->fire_enabled,
           (int)top->fire_req_valid, (int)top->fire_req_ready, (int)top->fire_outstanding, (int)top->fire_priv);
  (void)prev_watch_resp;
  printf("WATCH req=%lu wreq=%lu resp=%lu writes=%lu\n", (unsigned long)top->watch_req,
         (unsigned long)top->watch_wreq, (unsigned long)top->watch_resp, (unsigned long)top->watch_writes);
  // Was the instruction that was in flight when the interrupt fired allowed to finish, and is mepc the
  // instruction after it? This is the property the injection points exist to test.
  if (top->irq_fires && first_irq_epc) {
    uint64_t tpc = top->fire_pc;
    uint64_t n = pc_count.count(tpc) ? pc_count[tpc] : 0;
    printf("FIRE TARGET pc=0x%lx retired=%lu first_irq_epc=0x%lx faulted=%d\n",
           (unsigned long)tpc, (unsigned long)n, (unsigned long)first_irq_epc, (int)target_faulted);
  }
  if (crst_op) {
    if (!crst_cycle) { printf("CORE-RESET FAIL: the core was never in S_MUL on a %s (hits=%ld)\n", crst_op, crst_hits); if (rc == 0 || rc == 2) rc = 30; }
    else if (crst_bad_commit) { printf("CORE-RESET FAIL: a commit at 0x%lx appeared after the reset before the reset vector\n", (unsigned long)crst_bad_pc); if (rc == 0 || rc == 2) rc = 31; }
    else if (!crst_saw_reset_vector) { printf("CORE-RESET FAIL: no commit at the reset vector after the reset\n"); if (rc == 0 || rc == 2) rc = 32; }
    else if (pc_count.count(crst_pc) == 0) { printf("CORE-RESET FAIL: the interrupted instruction at 0x%lx never retired in the re-run\n", (unsigned long)crst_pc); if (rc == 0 || rc == 2) rc = 33; }
    else printf("CORE-RESET OK: reset at cycle %ld in %s (pc=0x%lx %s), no commit before the reset vector, re-run retired it %lu time(s), stale responses discarded by the bridge model=%lu\n",
                crst_cycle, !strcmp(crst_op, "if2") ? "S_IF2_WAIT" : !strcmp(crst_op, "ptw") ? "S_XLATE" : "S_MUL", (unsigned long)crst_pc, crst_op, (unsigned long)pc_count[crst_pc], (unsigned long)top->n_discard);
  }
  printf("TRAPS=%lu last_cause=%lu last_epc=0x%lx last_tval=0x%lx\n", (unsigned long)traps,
         (unsigned long)last_cause, (unsigned long)last_epc, (unsigned long)last_tval);
  printf("STATS req=%lu resp=%lu datareq=%lu retired=%lu cycles=%ld\n", (unsigned long)top->n_req,
         (unsigned long)top->n_resp, (unsigned long)top->n_data_req, (unsigned long)retired, cycles);
  if (roi_sym) {
    top->bd_rd_addr = (roi_sym - 0x80000000ULL) >> 3; top->eval();
    printf("ROI_MEASURED=%lu\n", (unsigned long)top->bd_rd_data);
  }
  if (have_expect_trap) {
    uint64_t at_epc = pc_count.count(top->trap_epc) ? pc_count[top->trap_epc] : 0;
    printf("COMMIT_AT_EPC=%lu\n", (unsigned long)at_epc);
    if (at_epc != 0) { printf("DIRECTED FAIL: the faulting instruction at 0x%lx retired %lu time(s)\n", (unsigned long)top->trap_epc, (unsigned long)at_epc); rc = 7; }
    else if (rc != 4) { printf("DIRECTED FAIL: expected a trap with cause %ld, none occurred\n", expect_trap); rc = 7; }
    else if ((long)top->trap_cause != expect_trap) { printf("DIRECTED FAIL: trap cause %lu, expected %ld\n", (unsigned long)top->trap_cause, expect_trap); rc = 7; }
    else { printf("DIRECTED OK: trap cause %ld as expected\n", expect_trap); rc = 0; }
  }
  if (have_expect_dreq) {
    uint64_t got = top->n_data_req;
    if ((long)got != expect_data_req) { printf("DIRECTED FAIL: %lu data requests reached the bus, expected %ld\n", (unsigned long)got, expect_data_req); if (rc == 0) rc = 8; }
    else printf("DIRECTED OK: %lu data requests as expected\n", (unsigned long)got);
  }
  if (expect_traps >= 0) {
    if ((long)traps != expect_traps) { printf("TRAP COUNT FAIL: %lu traps, expected %ld\n", (unsigned long)traps, expect_traps); if (rc == 0 || rc == 2) rc = 14; }
    else printf("TRAP COUNT OK: %lu\n", (unsigned long)traps);
  }
  if (have_target) {
    printf("CHAIN target_pc=0x%lx commit_cycle=%lu first_irq_cycle=%lu retired_at_irq=%lu\n",
           (unsigned long)target_pc, (unsigned long)tgt_commit_cycle,
           (unsigned long)first_irq_cycle, (unsigned long)tgt_retired_at_irq);
    if (tgt_reg_sampled)
      printf("CHAIN target_reg x%u=0x%lx at the interrupt\n", target_reg, (unsigned long)tgt_reg_at_irq);
    if (!first_irq_cycle) { printf("CHAIN FAIL: no interrupt was taken\n"); if (rc == 0 || rc == 2) rc = 23; }
    else if (!tgt_commit_cycle) { printf("CHAIN FAIL: the target instruction never retired\n"); if (rc == 0 || rc == 2) rc = 23; }
    else if (tgt_commit_cycle >= first_irq_cycle) {
      printf("CHAIN FAIL: the target retired at cycle %lu, not before the interrupt at %lu\n",
             (unsigned long)tgt_commit_cycle, (unsigned long)first_irq_cycle); if (rc == 0 || rc == 2) rc = 23;
    } else if (tgt_retired_at_irq != 1) {
      printf("CHAIN FAIL: the target had retired %lu times when the interrupt was taken, expected 1\n",
             (unsigned long)tgt_retired_at_irq); if (rc == 0 || rc == 2) rc = 23;
    } else if (have_target_reg && tgt_reg_at_irq != target_reg_val) {
      printf("CHAIN FAIL: x%u read 0x%lx at the interrupt, expected 0x%lx: the architectural update had not landed\n",
             target_reg, (unsigned long)tgt_reg_at_irq, (unsigned long)target_reg_val); if (rc == 0 || rc == 2) rc = 23;
    } else printf("CHAIN OK: target retired once at cycle %lu, interrupt at %lu, result already visible\n",
                  (unsigned long)tgt_commit_cycle, (unsigned long)first_irq_cycle);
  }
  if (exp_fire_write >= 0) {
    if (!top->irq_fires) { printf("FIRE WRITE FAIL: nothing fired\n"); if (rc == 0 || rc == 2) rc = 24; }
    else if ((int)top->fire_is_write != exp_fire_write) {
      printf("FIRE WRITE FAIL: the access in flight was a %s, expected a %s\n",
             top->fire_is_write ? "write" : "read", exp_fire_write ? "write" : "read");
      if (rc == 0 || rc == 2) rc = 24;
    } else if (have_target_addr && top->fire_addr != (uint32_t)target_addr) {
      printf("FIRE WRITE FAIL: the access in flight was at 0x%lx, expected 0x%lx\n",
             (unsigned long)top->fire_addr, (unsigned long)target_addr);
      if (rc == 0 || rc == 2) rc = 24;
    } else printf("FIRE WRITE OK: a %s at 0x%lx was in flight\n",
                  top->fire_is_write ? "write" : "read", (unsigned long)top->fire_addr);
  }
  if (exp_apply_events >= 0) {
    printf("APPLY events=%lu first=%lu second=%lu data1=0x%lx data2=0x%lx\n",
           (unsigned long)top->apply_seq, (unsigned long)top->apply1_cycle, (unsigned long)top->apply2_cycle,
           (unsigned long)top->apply1_data, (unsigned long)top->apply2_data);
    if ((long)top->apply_seq != exp_apply_events) {
      printf("APPLY FAIL: %lu write side effects at the watched address, expected %ld\n",
             (unsigned long)top->apply_seq, exp_apply_events);
      if (rc == 0 || rc == 2) rc = 25;
    } else printf("APPLY OK: %lu write side effects\n", (unsigned long)top->apply_seq);
  }
  if (have_exp_watch) {
    // Exactly once, measured on the bus and in the memory model -- not inferred from the final value, which
    // a duplicated store of the same value would leave untouched.
    long r = (long)top->watch_req, w = (long)top->watch_wreq;
    long q = (long)top->watch_resp, a = (long)top->watch_writes;
    if (r != exp_watch_req || w != exp_watch_wreq || q != exp_watch_resp || a != exp_watch_write) {
      printf("WATCH FAIL: req=%ld wreq=%ld resp=%ld writes=%ld, expected %ld/%ld/%ld/%ld\n",
             r, w, q, a, exp_watch_req, exp_watch_wreq, exp_watch_resp, exp_watch_write);
      if (rc == 0 || rc == 2) rc = 21;
    } else printf("WATCH OK: req=%ld wreq=%ld resp=%ld writes=%ld\n", r, w, q, a);
  }
  if (exp_fire_state) {
    const char* got = top->fire_state < 13 ? stn[top->fire_state] : "?";
    if (!top->irq_fires) { printf("FIRE STATE FAIL: the source was never raised\n"); if (rc == 0 || rc == 2) rc = 22; }
    else if (!top->fire_enabled) { printf("FIRE STATE FAIL: the source was raised while interrupts were not enabled\n"); if (rc == 0 || rc == 2) rc = 22; }
    else if (strcmp(got, exp_fire_state)) { printf("FIRE STATE FAIL: fired in %s, expected %s\n", got, exp_fire_state); if (rc == 0 || rc == 2) rc = 22; }
    else printf("FIRE STATE OK: %s with interrupts enabled\n", got);
  }
  if (expect_ints >= 0) {
    if ((long)interrupts != expect_ints) { printf("INTERRUPT COUNT FAIL: %lu, expected %ld\n", (unsigned long)interrupts, expect_ints); if (rc == 0 || rc == 2) rc = 19; }
    else printf("INTERRUPT COUNT OK: %lu\n", (unsigned long)interrupts);
  }
  if (min_irq_hits >= 0) {
    // the injection moment must actually have occurred, or the run proves nothing about that moment
    if ((long)top->irq_hits < min_irq_hits) { printf("IRQ COVERAGE FAIL: the injection moment occurred %lu times, needed at least %ld\n", (unsigned long)top->irq_hits, min_irq_hits); if (rc == 0 || rc == 2) rc = 20; }
    else printf("IRQ COVERAGE OK: the injection moment occurred %lu times\n", (unsigned long)top->irq_hits);
  }
  if (expect_cause >= 0) {
    long lc = (long)(last_cause & 0x7fffffffffffffffULL);
    if (lc != expect_cause || traps == 0) { printf("CAUSE FAIL: last cause %ld after %lu traps, expected %ld\n", lc, (unsigned long)traps, expect_cause); if (rc == 0 || rc == 2) rc = 15; }
    else printf("CAUSE OK: %ld\n", expect_cause);
  }
  for (auto& e : expect_csr) {
    // the real CSR register, read after the architectural update edge -- not a copy of the trap outputs
    top->bd_csr_sel = e.first; top->eval();
    uint64_t got = top->bd_csr_data;
    static const char* names[] = {"mstatus","mtvec","mepc","mcause","mtval","mscratch","mcycle","minstret","misa",
                                  "mie","mip","medeleg","mideleg","sstatus","sie","sip","stvec","sepc","scause","stval",
                                  "sscratch","satp","mcounteren","scounteren","priv"};
    if (got != e.second) { printf("CSR CHECK FAIL: %s = 0x%lx, expected 0x%lx\n", names[e.first], (unsigned long)got, (unsigned long)e.second); if (rc == 0 || rc == 2) rc = 16; }
    else printf("CSR CHECK OK: %s = 0x%lx\n", names[e.first], (unsigned long)got);
  }
  for (auto& e : expect_commit) {
    uint64_t got = pc_count.count(e.first) ? pc_count[e.first] : 0;
    if (got != e.second) { printf("COMMIT COUNT FAIL: pc 0x%lx retired %lu times, expected %lu\n",
                                  (unsigned long)e.first, (unsigned long)got, (unsigned long)e.second); if (rc == 0 || rc == 2) rc = 17; }
    else printf("COMMIT COUNT OK: pc 0x%lx retired %lu times\n", (unsigned long)e.first, (unsigned long)got);
  }
  if (expect_exit >= 0) {
    if (rc != expect_exit) { printf("EXPECTED-EXIT FAIL: got %d, expected %d\n", rc, expect_exit); rc = 9; }
    else { printf("EXPECTED-EXIT OK: %d\n", rc); rc = 0; }
  }
  if (memdumpfile) {
    FILE* m = fopen(memdumpfile, "w");
    if (!m) { printf("MEM DUMP FAIL: cannot write %s\n", memdumpfile); if (rc == 0) rc = 19; }
    else {
      fprintf(m, "# addr value  (the model's memory, read through the backdoor after the run)\n");
      for (uint64_t k = 0; k < memdump_n; k++) {
        uint64_t a = memdump_addr + 8 * k;
        top->bd_rd_addr = (a - 0x80000000ULL) >> 3; top->eval();
        fprintf(m, "0x%016lx 0x%016lx\n", (unsigned long)a, (unsigned long)top->bd_rd_data);
      }
      fclose(m); printf("MEM_DUMP_WORDS=%lu\n", (unsigned long)memdump_n);
    }
  }
  if (commitfile) {
    FILE* c = fopen(commitfile, "w");
    fprintf(c, "# pc insn rd value len  (rd is '-' when the instruction writes no register; len 2 = compressed parcel)\n");
    for (auto& e : commits)
      if (e.rdv) fprintf(c, "0x%016lx %08x x%-2u 0x%016lx %u\n", (unsigned long)e.pc, e.insn, e.rd, (unsigned long)e.val, e.len);
      else       fprintf(c, "0x%016lx %08x -   - %u\n", (unsigned long)e.pc, e.insn, e.len);
    fclose(c);
    printf("COMMIT_RECORDS=%zu\n", commits.size());
  }
  if (have_exp_reg) {
    top->bd_reg_addr = exp_reg; top->eval();
    uint64_t got = top->bd_reg_data;
    if (got != exp_reg_val) { printf("REG CHECK FAIL: x%u = 0x%lx, expected 0x%lx\n", exp_reg, (unsigned long)got, (unsigned long)exp_reg_val); if (rc == 0 || rc == 4) rc = 12; }
    else printf("REG CHECK OK: x%u = 0x%lx\n", exp_reg, (unsigned long)got);
  }
  if (tracefile) { FILE* t = fopen(tracefile, "w"); for (auto pc : trace) fprintf(t, "0x%lx\n", (unsigned long)pc); fclose(t); }
  if (roifile) {
    FILE* t = fopen(roifile, "r"); std::vector<uint64_t> exp; char line[128];
    while (t && fgets(line, sizeof line, t)) { if (line[0]=='#'||line[0]=='e') continue; exp.push_back(strtoull(line, nullptr, 0)); }
    if (t) fclose(t);
    if (exp.size() != trace.size()) { printf("ROI TRACE MISMATCH: got %zu entries, expected %zu\n", trace.size(), exp.size()); if (rc==0) rc = 6; }
    else { for (size_t i = 0; i < exp.size(); i++) if (exp[i] != trace[i]) { printf("ROI TRACE MISMATCH at %zu: got 0x%lx expected 0x%lx\n", i, (unsigned long)trace[i], (unsigned long)exp[i]); if (rc==0) rc = 6; break; } }
    if (rc == 0) printf("ROI TRACE OK: %zu commits match\n", trace.size());
  }
  top->final(); delete top;
  return rc;
}
