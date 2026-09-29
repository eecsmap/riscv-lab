#!/bin/bash
# PIPE-P2b checkpoint 4 judge over a gen-cp4.sh output directory (no generation; re-runnable on stored Verilog).
#   judge-gen.sh <gen outdir>        exit 0 = every existing configuration normalized-identical before/after with no
#                                    pipeline in it, both pipeline configurations instantiate tcpu_core_pipe (with
#                                    M, C, S/U, A) and never tcpu_core, all five refusals refused as named
# Normalization removes scala source locators only: `// @[File.scala l:c...]` comments, and the `(connected at
# File.scala:l:c)` locator the TileLink monitors embed in their assertion strings. Editing a scala file moves both.
set -u
OUT=${1:?gen outdir}
OLD="RD2Harness:RD2AtomicXv6FastConfig RD2Harness:RD2DualXv6FastConfig RD2Harness:RD2AtomicBootConfig RD2Harness:RD2DualBootConfig RD2Harness:RD2BootConfig RD2BoardTop:RD2AtomicBoardConfig RD2BoardTop:RD2DualBoardConfig"
norm() { sed -E 's#[[:space:]]*// @\[[^]]*\]##; s#\(connected at [A-Za-z0-9_]+\.scala:[0-9]+:[0-9]+\)#(connected at <scala>)#g' "$1"; }
bad=0
echo "== existing configurations: before vs after (raw, normalized)"
for tc in $OLD; do t=${tc%%:*}; c=${tc#*:}; vb=$OUT/before-$c/$t.$c.v; va=$OUT/after-$c/$t.$c.v
  if [ ! -s $vb ] || [ ! -s $va ]; then echo "  $c: MISSING generated Verilog"; bad=1; continue; fi
  cmp -s $vb $va && raw="raw identical" || raw="raw differs in $(diff $vb $va | grep -c '^[<>]') lines"
  diff <(norm $vb) <(norm $va) > $OUT/norm2-$c.diff && nm="normalized IDENTICAL" || { nm="normalized DIFFERS ($(grep -c '^[<>]' $OUT/norm2-$c.diff) lines)"; bad=1; }
  nc=$(grep -cE '^\s*tcpu_core\b' $va); np=$(grep -cE '^\s*tcpu_core_pipe\b' $va)
  { [ $nc -ge 1 ] && [ $np = 0 ]; } || bad=1
  echo "  $c: $raw; $nm; tcpu_core instances $nc, tcpu_core_pipe $np; sha before $(sha256sum $vb | cut -c1-16) after $(sha256sum $va | cut -c1-16)"
done
echo "== pipeline configurations"
for c in RD2PipeXv6FastConfig RD2PipeBootConfig; do v=$OUT/after-$c/RD2Harness.$c.v
  [ -s $v ] || { echo "  $c: MISSING"; bad=1; continue; }
  np=$(grep -cE '^\s*tcpu_core_pipe\b' $v); nc=$(grep -cE '^\s*tcpu_core\b' $v)
  hdr=$(grep -m1 -E '^\s*tcpu_core_pipe\b' $v | sed -E 's#[[:space:]]*// @\[.*##')
  ok=1; for p in "MISA_A(1)" "PIPE_EXT_SU(1)" "PIPE_EXT_M(1)" "PIPE_EXT_C(1)"; do echo "$hdr" | grep -qF ".$p" || ok=0; done
  { [ $np = 1 ] && [ $nc = 0 ] && [ $ok = 1 ]; } || bad=1
  echo "  $c: generated $(sha256sum $v | cut -c1-16); tcpu_core_pipe instances $np, tcpu_core instances $nc; parameters ok=$ok: $hdr"
done
echo "== refusals"
for c in MC1UnsupportedPipelineConfig P2bUnsupportedImplConfig P2bUnsupportedPipeV1Config MC2UnsupportedQuadConfig MC1UnsupportedZeroConfig; do
  l=$(grep -F "  $c: " $OUT/refuse.txt); echo "$l"; echo "$l" | grep -q ": refused: unsupported " || bad=1; done
echo "JUDGE_GEN $([ $bad = 0 ] && echo PASS || echo FAIL)"; exit $bad
