#!/usr/bin/env bash
# MC-M4 software: from the isolated copy sw/xv6 (= M3's tree + the TEACHING_VALIDATION switch + m3par2):
#   kernel-valid-4    validation kernel (getcpu/pin compiled in), 4 MiB   -- the M3 semantics, for the simulator
#   kernel-deploy-4   deployment kernel (no test mechanisms), 4 MiB       -- the simulator smoke test
#   kernel-deploy-128 deployment kernel (no test mechanisms), 128 MiB     -- the BOARD bundle (256 MiB DRAM window, kernel-128mib convention)
#   fs-valid.img      the M3 disk contents (B0 + m3 programs), fs-deploy.img = B0 + m3par2 + m3fs (no getcpu/pin users)
set -u; M4=/home/engineer/fpga/experiments/multicore/m4; X=$M4/sw/xv6; O=$M4/sw/out; rm -rf $O; mkdir -p $O
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
b() { local tag=$1; shift; (cd $X && make -B kernel/kernel fs.img CPPFLAGS="$*" > $O/build-$tag.log 2>&1) || { echo "BUILD FAIL $tag"; tail -3 $O/build-$tag.log; exit 1; }
  cp $X/kernel/kernel $O/kernel-$tag; cp $X/fs.img $O/fs-$tag.img; echo "$tag: kernel $(sha256sum $O/kernel-$tag | cut -c1-16) fs $(sha256sum $O/fs-$tag.img | cut -c1-16)  CPPFLAGS=$*"; }
b valid-4    -DTEACHING_SIM_MEM_MIB=4   -DTEACHING_PLATFORM_NO_PLIC_DEVICES -DTEACHING_VALIDATION
b deploy-4   -DTEACHING_SIM_MEM_MIB=4   -DTEACHING_PLATFORM_NO_PLIC_DEVICES
b deploy-128 -DTEACHING_SIM_MEM_MIB=128 -DTEACHING_PLATFORM_NO_PLIC_DEVICES
# the deployment disk: the same fs.img contents without the programs that need the validation syscalls
python3 - $X/Makefile <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("\t$U/_m3par\\\n\t$U/_m3migrate\\\n","").replace("\t$U/_m3exec\\\n",""); open(p,'w').write(s)
PY
(cd $X && make -B fs.img > $O/build-fs-deploy.log 2>&1) && cp $X/fs.img $O/fs-deploy.img && echo "fs-deploy: $(sha256sum $O/fs-deploy.img | cut -c1-16) (B0 apps + m3fs + m3par2 + xv6 utilities)"
git -C /home/engineer/fpga diff --no-index --stat $M4/sw/xv6/Makefile /dev/null >/dev/null 2>&1; (cd $X && git checkout -- Makefile 2>/dev/null || python3 - Makefile <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("\t$U/_b0file\\\n","\t$U/_b0file\\\n\t$U/_m3par\\\n\t$U/_m3migrate\\\n\t$U/_m3exec\\\n",1) if "_m3par\\" not in s else s; open(p,'w').write(s)
PY
)
mv $O/fs-valid-4.img $O/fs-valid.img; rm -f $O/fs-deploy-4.img $O/fs-deploy-128.img
riscv64-unknown-elf-nm -S $O/kernel-deploy-128 | grep -E " (scheduler|main)$" > $O/kernel-deploy-128.syms
# the deployment kernels differ from each other only by PHYSTOP: prove it on the disassembly
diff <(riscv64-unknown-elf-objdump -d $O/kernel-deploy-4 | sed 1,3d) <(riscv64-unknown-elf-objdump -d $O/kernel-deploy-128 | sed 1,3d) | grep -E '^[<>]' | grep -vE '^\s*$' > $O/deploy-4-vs-128.diff; echo "deploy-4 vs deploy-128 differing disassembly lines: $(wc -l < $O/deploy-4-vs-128.diff)"
diff -ru --exclude='*.o' --exclude='*.d' --exclude='*.asm' --exclude='*.sym' --exclude='_*' --exclude='fs.img' --exclude='mkfs' --exclude='__pycache__' --exclude='initcode*' --exclude='usys.S' /home/engineer/fpga/experiments/multicore/m3/sw/xv6 $X | grep -v '^Binary files .*kernel/kernel differ' > $O/xv6-m3-to-m4.patch; echo "diff vs the M3 tree: $(grep -c '^diff -ru' $O/xv6-m3-to-m4.patch) changed files, $(grep -c '^Only in' $O/xv6-m3-to-m4.patch) new, $(grep -cE '^[-+][^-+]' $O/xv6-m3-to-m4.patch) lines"
(cd $O && sha256sum kernel-* fs-*.img > sha256.txt); cut -c1-16,66- $O/sha256.txt; echo "SW_BUILD_DONE"
