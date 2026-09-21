# teaching-cpu-work manifest 2026-09-14T21:00:03Z
rocket-chip copied from 7cd3352c3b802c3c50cb864aee828c6106414bb3 (2 dirty entries:  M firrtl  M riscv-tools )
testchipip copied from 8bf7e85ceb8a33ecca4234ab8edfca4206bc665b (1 dirty entries: ?? project/ )
pynqz1 (untracked board port) copied from xv6-on-rocket-pynq-z1 1b5c9711a8221c1c2d5762761b228e4f0b5f5097 board/, excluding Vivado project and bitstreams
rocket-chip submodule pointers:
   a86e38889302662db14b932e4e0d862290c01308 chisel3 (v3.1.0-RC2^2^2)
   1d4914c396881c66aceb47d5cdd8740ad9a5be26 firrtl (v1.1.1~5^2~30)
   45f5ae171a1950389f1b239b46a9e0d16ae0a6f4 hardfloat (v1.2.0-RC1~8)
   8ad8d4839acf2cdac0129b8fed8fe12136e77307 riscv-tools (priv-1.7-191-g8ad8d48)
  -77195ab12aefc373ca688e0a9c4d710c13191341 torture
fpga-zynq: plain file copy (NOT a git worktree) of 726eb97185a74014ef3af059458db56d9ca25755; .git deliberately absent because sbt-git treats a worktree .git file as a bare repo and firrtl's build aborts (NoWorkTreeException).
excluded from the copy: common/linux-xlnx, common/u-boot-xlnx (PS software, not used by M1), rocket-chip/.git, */target, riscv-gnu-toolchain, emulator/verilator, pynqz1 Vivado project and bitstreams
prebuilt rocket-chip/lib/firrtl.jar (from the shared tree, built 2026-09-08) copied to rocket-chip/firrtl/utils/bin/firrtl.jar so the firrtl sbt build is never invoked
