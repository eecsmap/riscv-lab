// Is this physical address safe to hold in an instruction cache?
//
// A separate module so the decision is unit-testable on its own, and so the DEFAULT is visible: it is
// NOT cacheable. A region nobody thought about is never silently cached.
//
// DRAM is cacheable. The CLINT is not -- mtime advances with nobody writing it, so a cached copy is a
// stale clock -- and neither is anything else. The teaching SoC's map is small enough to state rather
// than parameterise, and stating it is the point.
`timescale 1ns/1ps
module tcpu_cacheable (
  input  [31:0] pa,
  output        cacheable
);
  // DRAM, as the adapter presents it to the core: {4'd1, addr[27:0]} -> 0x1000_0000 .. 0x1fff_ffff,
  // and the harness's own RAM at 0x8000_0000 .. 0x8fff_ffff, which is where the probes and xv6 run.
  wire in_dram   = (pa[31:28] == 4'h1) || (pa[31:28] == 4'h8);
  // CLINT: 0x0200_0000 .. 0x0200_ffff
  wire in_clint  = (pa[31:16] == 16'h0200);
  assign cacheable = in_dram & ~in_clint;
endmodule
