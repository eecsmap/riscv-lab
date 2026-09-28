#!/usr/bin/env bash
# MC-M3 software: the production dual-capable kernel + disk, and the two HTIF race TEST kernels, all from
# the isolated copy sw/xv6 (the baseline copy reproduced the accepted kernel-4mib / fs-b0-pristine byte for
# byte before any edit: sw/build-baseline.log, sw/kernel-baseline, sw/fs-baseline.img).
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; X=$M3/sw/xv6; O=$M3/sw/out; rm -rf $O; mkdir -p $O
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
b() { local tag=$1; shift; (cd $X && make -B kernel/kernel fs.img CPPFLAGS="$*" > $O/build-$tag.log 2>&1) || { echo "BUILD FAIL $tag"; tail -3 $O/build-$tag.log; exit 1; }
  cp $X/kernel/kernel $O/kernel-$tag; cp $X/kernel/kernel.asm $O/kernel-$tag.asm 2>/dev/null; cp $X/fs.img $O/fs-$tag.img; echo "$tag: kernel $(sha256sum $O/kernel-$tag | cut -c1-16) fs $(sha256sum $O/fs-$tag.img | cut -c1-16)  CPPFLAGS=$*"; }
b prod     -DTEACHING_SIM_MEM_MIB=4 -DTEACHING_PLATFORM_NO_PLIC_DEVICES
b racepos  -DTEACHING_SIM_MEM_MIB=4 -DTEACHING_PLATFORM_NO_PLIC_DEVICES -DTEACHING_HTIF_RACE_TEST
b raceneg  -DTEACHING_SIM_MEM_MIB=4 -DTEACHING_PLATFORM_NO_PLIC_DEVICES -DTEACHING_HTIF_RACE_TEST -DTEACHING_HTIF_RACE_NEG
cp $M3/sw/fs-baseline.img $O/fs-baseline.img; cp $M3/sw/kernel-baseline $O/kernel-baseline
riscv64-unknown-elf-nm $O/kernel-prod | grep -E " (scheduler|swtch|main|userinit|kinit)$" > $O/kernel-prod.syms
riscv64-unknown-elf-nm -S --size-sort $O/kernel-prod | grep -E " scheduler$" >> $O/kernel-prod.syms
(cd $O && sha256sum kernel-* fs-*.img > sha256.txt)
# the source difference against the shared baseline tree (the copy of record), as a unified diff
# (an earlier version excluded the NAME 'kernel' to drop the binary and thereby dropped the whole kernel/ directory)
diff -ru --exclude='*.o' --exclude='*.d' --exclude='*.asm' --exclude='*.sym' --exclude='_*' --exclude='fs.img' --exclude='mkfs' --exclude='__pycache__' --exclude='initcode*' --exclude='usys.S' /home/engineer/fpga/teaching-cpu-work/xv6-teaching $X | grep -v '^Binary files .*kernel/kernel differ' > $O/xv6-diff.patch; echo "diff: $(grep -c '^diff -ru' $O/xv6-diff.patch) changed files, $(grep -c '^Only in' $O/xv6-diff.patch) new files, $(grep -cE '^[-+][^-+]' $O/xv6-diff.patch) changed lines"
cat $O/sha256.txt | cut -c1-16,66-; echo "SW_BUILD_DONE"
