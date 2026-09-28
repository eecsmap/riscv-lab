#!/bin/bash
# MC-PERF software: the SAME deployment kernel as M4/M5 (must reproduce kernel-dual-128mib 33021237... byte for byte: the
# perf programs are user programs, the kernel is untouched), a 4 MiB kernel for the short simulation, and fs-perf.img
# (fs-deploy programs + perfcompute + perfarray). Isolated tree perf/sw/xv6 (copy of m4/sw/xv6).
set -u; P=/home/engineer/fpga/experiments/multicore/perf; X=$P/sw/xv6; O=$P/sw/out; rm -rf $O; mkdir -p $O
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
b() { local tag=$1; shift; (cd $X && make -B kernel/kernel fs.img CPPFLAGS="$*" > $O/build-$tag.log 2>&1) || { echo "BUILD FAIL $tag"; tail -3 $O/build-$tag.log; exit 1; }
  cp $X/kernel/kernel $O/kernel-$tag; cp $X/fs.img $O/fs-$tag.img; echo "$tag: kernel $(sha256sum $O/kernel-$tag | cut -c1-16) fs $(sha256sum $O/fs-$tag.img | cut -c1-16)  CPPFLAGS=$*"; }
b deploy-4   -DTEACHING_SIM_MEM_MIB=4   -DTEACHING_PLATFORM_NO_PLIC_DEVICES
b deploy-128 -DTEACHING_SIM_MEM_MIB=128 -DTEACHING_PLATFORM_NO_PLIC_DEVICES
# the perf disk must not carry the validation-only programs (m3par/m3migrate/m3exec need getcpu/pin): same exclusion as M4
python3 - $X/Makefile <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("\t$U/_m3par\\\n\t$U/_m3migrate\\\n","").replace("\t$U/_m3exec\\\n",""); open(p,'w').write(s)
PY
(cd $X && make -B fs.img > $O/build-fs-perf.log 2>&1) && cp $X/fs.img $O/fs-perf.img && echo "fs-perf: $(sha256sum $O/fs-perf.img | cut -c1-16)"
python3 - $X/Makefile <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
if "_m3par\\" not in s: s=s.replace("\t$U/_b0file\\\n","\t$U/_b0file\\\n\t$U/_m3par\\\n\t$U/_m3migrate\\\n\t$U/_m3exec\\\n",1); open(p,'w').write(s)
PY
rm -f $O/fs-deploy-4.img $O/fs-deploy-128.img
# Codex timebase fix: the MEASUREMENT kernel adds one read-only syscall (mtime) and is therefore NOT the accepted kernel-dual-128mib
# (33021237...). Both board configurations must run THIS kernel; its hash is frozen in sha256.txt. Record the diff to the accepted one.
M4K=/home/engineer/fpga/experiments/multicore/m4/deploy/kernel-dual-128mib
echo "measurement kernel kernel-deploy-128: $(sha256sum $O/kernel-deploy-128 | cut -c1-16) (accepted M5 kernel: $(sha256sum $M4K | cut -c1-16); differs by design: +sys_mtime)"
cmp -s $O/kernel-deploy-128 $M4K && echo "UNEXPECTED: kernel identical to the accepted one (the mtime syscall is missing?)"
diff <(riscv64-unknown-elf-objdump -d $M4K | sed 1,3d) <(riscv64-unknown-elf-objdump -d $O/kernel-deploy-128 | sed 1,3d) | grep -cE '^[<>]' | xargs -I{} echo "disassembly lines differing from the accepted kernel: {}"
(cd $O && sha256sum kernel-* fs-*.img > sha256.txt); cut -c1-16,66- $O/sha256.txt
diff -ru --exclude='*.o' --exclude='*.d' --exclude='*.asm' --exclude='*.sym' --exclude='_*' --exclude='fs.img' --exclude='mkfs' --exclude='__pycache__' --exclude='initcode*' --exclude='usys.S' --exclude='kernel' /home/engineer/fpga/experiments/multicore/m4/sw/xv6 $X > $O/xv6-m4-to-perf.patch; echo "diff vs the M4 tree: $(grep -c '^diff -ru' $O/xv6-m4-to-perf.patch) changed, $(grep -c '^Only in' $O/xv6-m4-to-perf.patch) new"
echo SW_BUILD_DONE
