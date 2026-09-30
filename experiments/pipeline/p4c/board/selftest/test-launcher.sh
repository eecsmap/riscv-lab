#!/bin/bash
# Offline self-test of xv6-pipe-dual.sh under busybox sh: a sandboxed copy (board paths rewritten into a temp dir, a
# stub host named fesvr-teaching-static that records its arguments and the lock state it saw).  test-launcher.sh [launcher]
L0=$(readlink -f "${1:-$(dirname "$0")/../xv6-pipe-dual.sh}"); bad=0
T=$(mktemp -d); X=$T/xv6run; mkdir -p $X $T/lockdir; echo 1 > $T/pd
sed -e "s#/root/xv6run#$X#g" -e "s#/sys/devices/amba.1/f8007000.devcfg/prog_done#$T/pd#g" -e "s#/var/lock#$T/lockdir#g" "$L0" > $X/l.sh
cat > $X/fesvr-teaching-static <<STUB
#!/bin/sh
echo "ARGS \$*" >> $T/host.log; echo "LOCKOWNER \$(cat $T/lockdir/teaching-fesvr.lock/owner 2>/dev/null)" >> $T/host.log
[ -n "\$STUB_SLEEP" ] && sleep "\$STUB_SLEEP"; exit 0
STUB
chmod +x $X/fesvr-teaching-static; echo k > $X/kernel-perf-128mib; echo user > $X/fs-user.img
cp "${P4C_WS:-/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline/p4c/ws}/artefacts/fs-perf.img" $X/fs-bench-pristine.img || { echo "FAIL no fs-perf.img in the workspace"; exit 1; }
t() { local name=$1 want=$2 pat=$3; shift 3; : > $T/host.log; out=$(cd $X && "$@" 2>&1); rc=$?
  if [ $rc = $want ] && grep -q -- "$pat" <<<"$out$(cat $T/host.log)"; then echo "ok   $name"; else echo "FAIL $name rc=$rc (want $want, '$pat'): $out | $(cat $T/host.log)"; bad=$((bad+1)); fi; }
lockfree() { [ ! -e $T/lockdir/teaching-fesvr.lock ] && echo "ok   lock free after: $1" || { echo "FAIL lock left after: $1"; bad=$((bad+1)); rm -rf $T/lockdir/teaching-fesvr.lock; }; }
t check 0 "CHECK OK" busybox sh l.sh --check
t default 0 "ARGS +blkdev=$X/fs-user.img $X/kernel-perf-128mib" busybox sh l.sh; lockfree default
grep -q "LOCKOWNER user-interactive xv6-pipe-dual.sh" $T/host.log && echo "ok   lock held while the host ran" || { echo "FAIL lock not held while the host ran"; bad=$((bad+1)); }
t other-disk 0 "ARGS +blkdev=$X/fs-user.img" busybox sh l.sh $X/fs-user.img; lockfree other-disk
echo scribbled > $X/fs-bench.img
t bench 0 "ARGS +blkdev=$X/fs-bench.img" busybox sh l.sh --bench; lockfree bench
cmp -s $X/fs-bench.img $X/fs-bench-pristine.img && echo "ok   --bench re-made fs-bench.img from the pristine copy" || { echo "FAIL fs-bench.img is not the pristine copy"; bad=$((bad+1)); }
cp $X/fs-bench-pristine.img $T/p.bak; printf 'x' >> $X/fs-bench-pristine.img
t bench-pristine-changed 1 "pristine benchmark disk is missing or changed: not starting" busybox sh l.sh --bench; lockfree bench-pristine-changed
t check-pristine-changed 1 "missing or changed" busybox sh l.sh --check; cp $T/p.bak $X/fs-bench-pristine.img
t missing-disk 1 "missing disk" busybox sh l.sh $X/nope.img
echo 0 > $T/pd; t not-programmed 1 "prog_done=0" busybox sh l.sh; echo 1 > $T/pd
mkdir $T/lockdir/teaching-fesvr.lock; echo agent > $T/lockdir/teaching-fesvr.lock/owner
t lock-held 1 "is held (agent)" busybox sh l.sh; t lock-held-check 1 "is held" busybox sh l.sh --check; rm -rf $T/lockdir/teaching-fesvr.lock
# a host already running (the stub, whose comm is "fesvr-teaching-") must be refused, lock untouched
( cd $X && STUB_SLEEP=4 ./fesvr-teaching-static > /dev/null 2>&1 & ); sleep 0.5
t host-running 1 "a host is already running" busybox sh l.sh; lockfree host-running; sleep 4
# Ctrl-C: the terminal sends SIGINT to the whole foreground process group; the host dies, the launcher releases the lock
# (started in its OWN new session by Python and signalled by that session id only: the first version signalled this
# test's own process group)
( cd $X && STUB_SLEEP=30 python3 -c '
import subprocess, time, os, signal, sys
p = subprocess.Popen(["busybox", "sh", "l.sh"], stdout=open(sys.argv[1], "w"), stderr=subprocess.STDOUT, start_new_session=True)
time.sleep(1.5); assert os.getpgid(p.pid) == p.pid != os.getpgid(0); os.killpg(p.pid, signal.SIGINT)
try: p.wait(10)
except subprocess.TimeoutExpired: os.killpg(p.pid, signal.SIGKILL); print("launcher did not exit after SIGINT", file=open(sys.argv[1], "a"))
' $T/int.out )
grep -q "lock released" $T/int.out && echo "ok   Ctrl-C: host exited, 'lock released' printed" || { echo "FAIL Ctrl-C: $(cat $T/int.out)"; bad=$((bad+1)); }; lockfree ctrl-c
echo "SELFTEST $([ $bad = 0 ] && echo PASS || echo "FAIL $bad")"; [ $bad = 0 ]
