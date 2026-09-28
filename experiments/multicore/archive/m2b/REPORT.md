# MC-M2b — 两个真实多周期核,裸机仿真:交付报告

任务:`.coord/proposals/codex-mc-m2b-real-dual-baremetal.md`(已 ack)。工作树 `worktrees/mc-dual-core`(分支 `mc-dual-core`,基于 MC-M2a 验收提交 `33c4864`)。**未推送、未打 tag;未触碰板卡/串口/Pmod;未运行 Vivado;未改 xv6/host 软件;未清理旧产物;共享 `fpga-zynq` 树未写(非 git 仓库,证据见 §7.12)。**

## 1. 范围与结论(摘要;数字见 §7 与 `RESULTS.md`)

- RD2 实际链上 **两个 `TeachingHart`**(HART_ID 0/1,各自 8 项 TLB、1 KiB I-cache——`TeachingCpuV2` 的 BlackBox 每实例独立),两个系统总线端口,CLINT 每 hart `msip/mtimecmp`,PLIC 每 hart 一个 M 态上下文,后端按**精确 client 名**绑定两 hart(`TeachingHart.clientName(i)` 同时决定桥的 client 名与后端 `cpuClientNames`,由同一 `numCores` 派生,不排序),一个**对齐**的全局 drain/apply(C7.1)。
- 单核可配置保留(`numCores = 1`,同一代码路径,client 名变为 `teaching-phys-0`);`NUM_CORES` 仅 1/2 可用,`pipeline`/0/4 在 elaboration 拒绝且消息含值。
- 双核裸机程序 7 个(启动/栈、CLINT、锁与原子、pbus/PLIC、fence.i、drain、长跑)+ 4 个注入缺陷的负向程序;判定器 `dual_check.py` 以事件 trace(逐 hart)、harness 的每 hart 计数(`HARTS` 行)、退出码与程序控制台**同时**判定,不凭字符串;判定器变异自测 + 注入负向。
- 单核回归:从本工作树重生成 `RD2AtomicXv6FastConfig`/`RD2AtomicBootConfig`,13 短探针与 M1 closeout2 比较、R-BOOT 四门;原 CPU-A 27 场景与 M2a 定向/kill 组在本 common 上重跑。
- 旧 SU/M/C 核级套件失败**仍列为基线未解决**(M1 T1.4 的归类不变;本包不宣称全 ISA 绿)。

## 2. 设计(`git diff 33c4864 -- soc/`)

### 2.1 `TeachingHart.scala`
- `object TeachingHart { clientName(h) = s"teaching-phys-$h"; clientNames(n) }`:**hart→client 名→后端槽**的唯一来源(C3.1/D4)。
- `require(hartId >= 0)`(M1 的 `hartId == 0` 限制取消);桥 `RD2BridgeV2(..., clientName = clientName(hartId), hartId)`;watcher 名 `cpu$hartId`;新增输出 `maxAWait`(该 hart 的 A 被连续挂起的最长拍数;1 = 当拍被接受),作为公平性证据。

### 2.2 `AtomicHub.scala`
`WithAtomicHub(cpuClientNames: Option[Seq[String]] = None)`:`None` ⇒ `TeachingHart.clientNames(p(RD2Key).numCores)`——后端绑定的名字与 SoC 造 hart 用的是同一个函数、同一个 `numCores`,不可能漂移;`numCores = 0` 在此处即以 `unsupported NUM_CORES=0` 拒绝(这个闭包比 `RD2ZynqTop` 的检查先 elaborate)。`AtomicSoc.scala` 的单桥 harness 改用 `clientName(0)`(CPU-A 27 场景重跑验证)。

### 2.3 `RD2Soc.scala`
- **矩阵**:`require(numCores == 1 || numCores == 2, "unsupported NUM_CORES=…: MC-M2b implements 1 and 2 (4 is not implemented)")`;`MC1UnsupportedDualConfig` 移除(双核已实现),新增 `MC2UnsupportedQuadConfig`(4)。
- **端口**:`harts.zipWithIndex.foreach { sbus.fromPort(Some(s"teaching-cpu-$i"))() := h.node }`;**中断**:`clintSinks/plicSinks = Seq.fill(nHarts)(IntSinkNode(...))`,hart i 取 sink i 的 `msip/mtip`、`meip`(C8.3/C8.4);`backend.module.io.sb(i) <> hart(i).io.sb`,并 `require(backend.numHarts == nHarts)`。
- **C7.1 对齐 drain**:`applyingAll = AND(bridge.applying)`,`anyPending = OR(pendingA||outstanding)`;`holdAll` 从看到 `softReset` 起把每个桥的 `softReset` 输入拉高,直到所有桥都 applying 且已 applying `applyCycles` 拍,之后交还 host 的电平——先 drain 完的桥不能先释放其核;`cpuRestartSafe = applyingAll && applyCnt ≥ 1 && !anyPending`;`rd2clint.applyReset` 取 `applyingAll` 上升沿一次(C7.2);`status.msip` 仍是 hart 0 的(C7.3/D5)。**`holdAll` 只在 `nHarts > 1` 时 elaboration**:单核保持 M1 验收时的逐字节行为(首轮它对单核也生效,把 host 3 拍装载复位后的释放推迟了 1 拍,`ext04_sv39` 的轮询循环因此多转 5 圈——§9-7;单核下没有需要对齐的第二个桥)。
- **状态不冒充**:`draining/timeout/pendingA/outstanding/pendingWork/writeInFlight/dramWriteInFlight` 为各 hart 的 OR,`nDrained/aWaits/aFires/dFires` 为和,`epoch` 取 hart 0(对齐后相等;若不等打印 `RD2 EPOCH_SKEW`),新增 `status.allPending`(所有 hart 都有在途)供注入器条件 10 使用。
- **观察/事件**:`EV`/`RD2` 事件逐 hart 生成,`nHarts > 1` 时在 tag 后带 `hart=i `;单核文本**逐字节不变**(M1 比较器直接复用,§7.9 证明);`RESET_APPLY/CLINT_APPLIED/SAFE_DROP/CPU_RESTART_SAFE` 全局一次;新增 SoC 输出 `obsAll/maxAWaitOut/aWaitsOut/epochOut`,`halted` = 所有 hart halted,`busy` = 任一 hart busy。
- **Harness**:`RD2Harness` 新增 `obsRetiredH/obsPcH/obsTrapsH/obsTrapCauseH/maxAWaitH/aWaitsH/epochH`(`Vec(nH)`),注入器条件 `+rd2_reset_when=10`(所有 hart 在途)。
- **配置**:`RD2DualBootConfig`(事件 trace + 后端 AT trace + TL monitor)、`RD2DualXv6FastConfig`(无 trace 无 monitor)。

### 2.4 未改
RTL(`rtl/cpu` 与 M1/M2a 同一 sha);`RD2BridgeV2`、`AtomicBackend`(M2a 版)、ISA、访存路径、无 D-cache/流水线;host/fesvr 协议(仍只写 `msip[0]`,ROM 唤醒其余 hart)。

## 3. 双核裸机程序(`progs/`,rv64imac_zicsr_zifencei,lp64,无 libc)

公共:`link.ld`(**不用 .bss**——hart 1 可能在 hart 0 清零前就写共享字,所有共享变量在 `.data` 显式初值;两个 4 KiB 栈 `_stack_base + 4K·h`)、`start.S`(每 hart 由 `mhartid` 取栈,装默认 trap 向量 `trap_default`——意外 trap 在 hart 0 上打印 `M2B-TRAP-FAIL` 退出 99,而不是掉回 ROM 静默重启)、`htif.S`(仅 hart 0 写 `tohost`;加 `htif_puthex`)、`dual.h`(`BARRIER` 用 `amoadd.w.aqrl` 到达计数 + 自旋,`WAIT_EQ` 获取侧 fence)。**只有 hart 0 写 tohost**;hart 1 的结果经共享内存/屏障归并到 hart 0。

| 程序 | 覆盖 | 关键断言(程序内) | 判定器额外规则(trace) |
| --- | --- | --- | --- |
| `dual01_boot` | T3.1 ROM 唤醒、T3.2 独立栈 | 两 hart 记录入口、sp、各写 8 个栈 canary,屏障后互读对方 canary、自身 canary 完好;hart 1 的 sp 在其栈区 | 两 hart 都在 `0x80000000` 退休;hart 0 写 `msip[1]=1`、探测 `msip[2]`(写 1 回读 **0、无错误**)、**没有**写 `msip[3]`(探测止于 NUM_CORES;U1 实证)、清 `msip[0]` 后 hart 1 才入口;COMMIT 数逐 hart 等于 `HARTS` |
| `dual02_clint` | T3.3 每核 timer/msip | 各 hart 自设 `mtimecmp[h]`,handler 计数 mtip ≥ 5 后停表;hart 0 忙 3000 圈后写 `msip[1]`,hart 1 忙等中计进度并被 IPI 唤醒 | 程序阶段 hart 0/1 各 ≥5 次 `cause=0x8…7`;hart 1 恰 1 次 `cause=0x8…3`,hart 0 0 次;`IRQLEVEL hart=1 msip=1` 在 hart 0 写 `msip[1]` 之后;`HARTS traps1 ≥ 7` |
| `dual03_lock` | T3.4 C5/C6 | P1 `amoswap` 锁保护 ld/sd 计数 10000/核 → 20000;P2 一个字上 LR/SC 各 10000 次成功 → 20000,记录失败次数;P3 `amoadd` 20000;P4 **独立 granule** LR/SC 各 10000,失败必须为 0;P5 发布/获取 2000 轮(`sd data; fence w,w; sd flag` / `ld flag; fence r,r; ld data`),data 必等于 f(flag);P6 hart 1 读 `0x50000000` → cause 5/tval,hart 0 写 `0x50000008` → cause 7/tval,各恰 1 次 | trace 配置:每 hart 恰一次访问故障且 cause/tval 正确;后端 AT 行 `SC_OK hart=h ≥ 20000`、`AMO_START hart=h ≥ 20000` |
| `dual04_pbus` | T3.5 C6.4、U2 | 200 轮:自身 `mtimecmp` 写读、`mtime`、xv6 将用的 S 态 PLIC 地址(`0xC002080+h·0x100`,`0xC201000+h·0x2000`)与 M 态地址写读、DRAM;**任何 trap 都判失败**;PLIC S 态地址回读值**报告**而不断言 | 程序阶段无 trap |
| `dual05_fencei` | T3.6 C10 | hart 1 先调用 X(`li a0,1; ret`)4 次预热;hart 0 改写 X 为 `li a0,2`、fence、置 flag;hart 1 (a) 不 `fence.i` 调 X 记录结果(实现实验,如实报告),(b) `fence.i` 后调 X **必须**得 2 | hart 1 写前对 X 行的取指次数 **<** 执行次数(预热证据);写后 `COMMIT hart=1 pc=X insn=0x00200513`(新码退休);`fence.i` 退休后有对 X 的新取指 |
| `dual06_drain`(v2,复审后) | C7 两真核**写**在途 drain | 每 hart 向 **ELF 映像之外**的私有 scratch 区(`0x80020000 + h·0x4000`,host 重装载不会覆盖)顺序 `sd` 2048 个模式字 `0xA5<<56 | h<<48 | i`,每 16 字一次 `amoadd`(`0x80028000 + h·64`);epoch 字 `0x80028100`(映像外)首轮写 MAGIC;第二轮先数自己区域从 0 起连续正确的**幸存前缀**再重跑流;hart 0 报告 `epoch survived0 survived1` | `+rd2_reset_at=46000 +rd2_reset_when=10 +rd2_reset_len=0 +rd2_reload_after_inject=1`(注入落在写流中)。**无条件**核验:注入恰 1 次;每 hart `HOLD_ASSERT`/`DRAIN_DONE`/`HOLD_RELEASE` 各恰 1 次,`RESET_APPLY`、`CPU_RESTART_SAFE` 各恰 1 次;两 assert 同拍;DRAIN_DONE 不早于 assert;apply 不早于两者 DRAIN_DONE;SAFE 在两者 DRAIN_DONE 与 apply 之后;release 在 apply 与 SAFE 之后,两 release 相距 ≤ applyCycles;释放后无陈旧响应(任何 RESP 都绑定到 `(hart, epoch, seq)`,hold 前的请求不得在释放后被应答,无重复应答);**每笔 CPU DRAM 写 `(hart, epoch, seq)` 绑定到恰一笔 AXI 写(AW 地址 + W strb/数据 + 该 id 的 B resp=0,在其 RESP 之前;AMO 只绑地址/lane)**,CPU 专用区内任何无对应请求的 AXI 写都是重复/伪造;每 hart 在 hold 时**恰一笔在途且必须是 DRAM 写**,它不得被应答(被 drain 丢弃),其 AXI 完成必须在该 hart 的 DRAIN_DONE 之前,`nDrained ≥ 1`;程序读回的幸存前缀 == 该 hart 在 hold 前发出的 **scratch 普通写**数(不含 amo 字;本次运行中在途的是 AMO,故幸存字全部是 hold 前已应答的普通写),精确相等 |
| `dual07_long` | T3.7 长期进度 | 每 hart 100000 圈 ×11 条指令(ALU/自身数组 ld/sd/每 64 圈 amoadd),屏障后报告两 hart 的迭代计数与校验和 | `HARTS retired0/1 ≥ 1,000,000`;报告中两 hart 迭代计数都必须为 100000(归并完成状态);报告 `maxawait/awaits` |
| `neg01_nohart1` | 负向:hart 1 不到达 | hart 0 在屏障挂起 → 超时 | 判定器必须拒绝(超时不是通过) |
| `neg02_wronghart` | 负向:错 hartid | 两 hart 都走 hart-0 路径 | 拒绝 |
| `neg03_wrongcount` | 负向:错终值 | hart 1 少加 1 且程序不自检,标记仍 OK | 判定器按数值拒绝 |
| `neg04_early` | 负向:早结束 | hart 0 不等屏障即报告;hart 1 工作量 2×(否则两核同时完成,早结束不可见——§9-6) | 报告中 hart 1 迭代计数为 0 → 拒绝(`retired1` 此时已 ≥1 M,单看退休数抓不住) |

## 4. 判定器与工具(`tests/`)

- `run-dual.sh <sim> <elf> <out> <max-cycles> <wall> [plusargs]`:仿真 stdout+stderr 合流(Verilator 的 `printf` 走 stderr),`trace_aggregate.py` 计数、`events.txt`(EV/RD2/RD2H/RD2HOST/RBOOT/EVH,允许前缀有程序字符)、`console-clean.txt`(程序自身字符的**逐行恢复**:带 trace 记号的行只保留记号前的字符——与 M1 `probe_console.py` 同法)、`final.txt`、`exit`、`verdict.txt`。
- `dual_check.py <run> --prog <p> [--fast] [--elf] [--drain] [--min-retired] [--atomic-floor]`:§3 表中的规则;通用规则:exit 0、`Completed after`、`HOSTDONE`、`HARTS n=2` 且两 hart retired ≥ 阈值、末 epoch 相等、(trace)两 hart 入口退休 + ROM 协议 + 逐 hart COMMIT 数 == HARTS + 无 `EPOCH_SKEW`。
- `dual-check-selftest.sh`:对真实通过日志的 16 种变异(19/19 含 3 基线)(缺 hart 1 退休、`HARTS n=1`、`retired1=0`、标记缺失/篡改、无 Completed/exit≠0/无 HOSTDONE、缺 msip[1] 写、hart 1 早于 msip[0] 清零、sp 越界、COMMIT 数≠HARTS、缺 IPI trap、timer 计数篡改、缺新码退休、fence 结果篡改、缺 fence.i)各按其原因拒绝;`m2b-suite.sh neg`:4 个注入缺陷程序真实运行并被拒绝。`drain-check-selftest.sh`(复审后新增):对真实通过的 dual06 v2 记录做 15 种变异——删 RESET_APPLY、删 CPU_RESTART_SAFE、apply 提前到某 hart DRAIN_DONE 之前、某 hart 提前释放、DRAIN_DONE 提前到在途写完成之前、丢一笔 CPU 写的 AXI 三元组、改其 W 数据、改其 AW 地址、丢在途写的 AXI 三元组、释放后交付陈旧响应、CPU 区多一笔无请求的 AXI 写、篡改幸存数、篡改 epoch、删一个 HOLD_ASSERT、末 epoch 不等——各按其原因拒绝(16/16 含基线)。
- `build-dual-sim.sh`(`build-xv6-sim.sh` 的副本,main 换为 `m2b_main.cpp`——`rd2_boot_main.cpp` 的副本加 `HARTS`/逐 hart PROGRESS,`-DM2B_NHARTS`)、`smoke2.sh`、`m2b-suite.sh`(seeds/long/drain/trace03/neg)、`n1-regress.sh`(矩阵拒绝 + RD2 单核回归 + CPU-A 27 + M2a 定向/kill)。

## 5. 预算与执行约束

`+max-cycles` 与墙钟均为 `run-dual.sh` 的显式参数:短程序 0.4–8 M 周期;dual03 60 M(20000 锁操作 ×3 访存 ×~30 拍 + 其余阶段 ≪);dual07 200 M(2.2 M 条指令 × 保守 CPI 30 × 3 余量),墙钟 5400 s;drain 4 M;trace 版 dual03 3600 s。所有构建/生成/长仿真经 `./coord job start`(`mc-m2b-compile-check-1`、`mc-m2b-smoke1/2/3`、`mc-m2b-n1-regress`、`mc-m2b-suite`),Verilator `-j 4`;超时按失败记,不重试。

## 6. 未确认项的核对(任务书第 4 条)

- **U1(ROM 探测 msip 边界)**:`RegMapper.scala:194` `out.bits.data := Mux(oRightReg(oindex), dataOut(oindex), 0)`——未映射偏移读 0、不置错;实测(dual01 trace):hart 0 写 `0x2000008`=1、回读 `rdata=0 error=0`、探测停止、无 `0x200000c` 写;两 hart 都到 `0x80000000`。**协议未改**(host 仍只写 `msip[0]`)。
- **U2 / PLIC 布局**:rocket PLIC 上下文数 = 连接的 sink 数 = 2(context 0 = hart 0 M 态,context 1 = hart 1 M 态);xv6 的 `PLIC_SENABLE(0) = 0xC002080` 恰是 **context 1(hart 1 的 M 态 enable)**——真实寄存器(dual04 回读 0x2),`PLIC_SENABLE(1) = 0xC002180` 是不存在的 context 3(回读 0、无错误);阈值 `0xC201000`(context 1)/`0xC203000`(不存在)同理。功能上本平台无任何设备中断,xv6 的 PLIC 写在双核下仍**不会 fault**,但 hart 0 的 S 态 enable 写会落到 hart 1 的 M 态 enable 上——记入 C8.4 未来 xv6 阶段注意事项,不凭单核推断。

## 7. 结果

所有数字来自 `runs/`(逐行见 `RESULTS.md`);**最终轮 = round 2**(`runs/smoke-r2`、`runs/suite-r2`、`runs/n1-r2`,scala 与提交 b147091 一致——仅 `AtomicBackend.scala` 的 RESV 诊断注释在提交中多改了 5 行注释,`runs/common-vs-commit.diff`,0 行非注释)。round 1(`runs/smoke3`、`runs/suite`、`runs/n1`)保留为历史,其差异见 §9。

| 组 | 运行 | 结果 |
|---|---|---|
| 7.1 启动与栈(T3.1/T3.2) | `smoke-r2/dual01_boot`,tracing sim | **PASS**,14,926 周期。两 hart 都在 `0x80000000` 退休(hart 0 先,hart 1 在 hart 0 清 `msip[0]` 之后);ROM 探测:写 `msip[1]`=1 → 回读 1,写 `msip[2]`=1 → **回读 0、error=0**,未写 `msip[3]`(U1 实证:探测止于 NUM_CORES);hart 1 sp=0x80003000 落在其栈区 [0x80002000,0x80003000];互读 canary 无交叉污染;`HARTS retired0=1650 retired1=2078`,与 trace 中逐 hart COMMIT 数相等 |
| 7.2 每核 timer/msip(T3.3) | `smoke-r2/dual02_clint` | **PASS**,314,002 周期。程序阶段 hart 0/1 各 5 次 `cause=0x8…7`;hart 1 恰 1 次 `cause=0x8…3`(IPI),hart 0 为 0;`IRQLEVEL hart=1 msip=1` 在 hart 0 写 `msip[1]` 之后;hart 1 忙等期间进度计数 0xa13(2,579 圈),hart 0 同时完成 3000 圈忙循环后才发 IPI——两核同时进展 |
| 7.3 锁/LR-SC/AMO/发布/错误(T3.4) | `suite-r2/dual03-s1..s10`(FAST sim,10 种 throttle 时序 `+rd2_a_delay/+rd2_d_delay/+rd2_throttle_from`),`suite-r2/dual03-trace`(tracing sim) | **11/11 PASS**。每次:lock=lrsc=amo=**0x4e20(20000)**;独立 granule LR/SC 失败 0;发布/获取 2000 轮无坏读;hart 0 store fault cause 7/tval 0x50000008、hart 1 load fault cause 5/tval 0x50000000 各恰 1 次。共享字 LR/SC 的失败数随时序变化:seed 1/4/8/9 为 0/0,seed 2 0x1a6/6,seed 3 0x12e5/0x1387,seed 5 1/1,seed 6 0xef8/0xefa,seed 7 0x130c/0x1218,seed 10 0x994/0x835——竞争确实发生且被 SC 语义正确处理。周期 4.04–5.53 M。tracing 交叉核对(后端 AT 行):`SC_OK hart=0/1` 各 **20000**,`AMO_START` 各 50,59x(锁 20000 + amoadd 10000 + 屏障等),`SC_FAIL` 0(该时序下无竞争,如实报告);`maxawait` 17/18,`awaits` 300k/305k(串行后端下的等待周期总数) |
| 7.4 pbus/PLIC(T3.5,U2) | `smoke-r2/dual04_pbus` | **PASS**,81,591 周期,两 hart 各 200 轮 CLINT/PLIC/DRAM 交替访问,程序阶段 **0 trap**。PLIC S 态地址回读(写 2/0 后):`0xC002080`→**0x2**(存在:它是 context 1 = hart 1 的 M 态 enable),`0xC002180`→0(不存在的 context 3,读 0 无错),`0xC201000`/`0xC203000`→0。见 §6 |
| 7.5 fence.i(T3.6) | `smoke-r2/dual05_fencei` | **PASS**,21,312 周期。hart 1 写前执行 X 4 次而对 X 行只取指 1 次(预热证据);hart 0 改写后 hart 1 **不 fence.i 时执行到旧码(返回 1)**——本实现实验结果,不作 ISA 断言;`fence.i` 退休后对 X 重新取指并退休 `insn=0x00200513`,返回 **2** |
| 7.6 两真核**写**在途 drain(复审后重瞄,`runs/drain2/dual06-drain`,dual06 v2,tracing sim,`+rd2_reset_at=46000 +rd2_reset_when=10 +rd2_reset_len=0 +rd2_reload_after_inject=1`) | **PASS(闭合规则)**。INJECT 46950 时 hart 0 的 `amoadd`(`0x80028000`)**已提供未被接受**(pendingA=1)、hart 1 的 `amoadd`(`0x80028040`)**已接受在途**(outstanding=1);`HOLD_ASSERT` 同拍 46951;`DRAIN_DONE hart=1` 46952、`hart=0` 46963(等到它的写完成);`RESET_APPLY` 46964(一次,晚于两者);`CPU_RESTART_SAFE` 46965;`HOLD_RELEASE hart=0/1` 同拍 46968,各 `nDrained=1`;两笔在途 **AMO** 都**未被应答**且各恰一次到达 AXI、完成于各自 DRAIN_DONE 之前——对 AMO 逐笔核的是**地址/lane/成功 B/完成时间**,不核数据(AMO 的算术数据语义由 M2a 单元 oracle 与双核锁测试 dual03 覆盖);**5,913 笔 CPU DRAM 写逐笔绑定到恰一笔 AXI 写**(普通 store 校地址/lane/数据/B=OKAY 且在 RESP 之前;AMO 校地址/lane/B),CPU 专用区无多余 AXI 写(6,274 笔 AXI 写含 host 装载);释放后无陈旧响应;重装载后第二轮程序读回:hart 0/1 各 **689** 个幸存模式字 == 各自 hold 前发出的 689 笔**普通 scratch 写**——这 689 字是此前普通写的读回,**不包含**那两笔在途 AMO(它们写的是 amo 字,不在 scratch 前缀里),drain 也**没有**独立验证 AMO 的计算数据(Codex M2b 验收边界,措辞随 M3 更正)。**旧记录 `suite-r2/dual06-drain` 用闭合规则重评为 FAIL**(`dual06-drain.recheck`):注入时(6004)两 hart 在途的是 ROM 等待循环的**取指**——host 尚在装载(入口在 41306),当时"两核在途"成立但不是写;且旧 runner 未保留 AXI 行——旧记录保留为历史,不作为 drain 证据 |
| 7.7 长期进度(T3.7) | `suite-r2/dual07-long`(FAST) | **PASS**,8,737,743 周期:`HARTS retired0=1,208,492 retired1=1,209,568`(各 ≥ 1 M),两 hart 迭代计数各 0x186a0(100000),校验和相等;`maxAWait` 11/9 拍,`aWaits` 39,574/39,424;实测 CPI ≈ 7.2(共享串行后端);预算 200 M 周期用了 4.4% |
| 7.8 判定器 | `runs/dual-check-selftest.txt`;`suite-r2/neg0*` | 变异自测 **19/19**(16 变异各按原因拒绝 + 3 基线接受);注入缺陷程序 **4/4 被拒**:neg01(hart 1 不到达)→ 超时无 host 结果(exit 2;超时按拒绝记);neg02(两 hart 都自认 hart 0)→ hart 0 走到默认 trap 向量 `M2B-TRAP-FAIL` exit 99;neg03(hart 1 少加 1、程序不自检)→ `lock-protected counter = 19999`;neg04(hart 0 不等屏障即报告,hart 1 工作量 2×)→ 报告中 hart 1 迭代数 0(而 `retired1` 已 1.2 M——只看退休数抓不住早结束,归并状态抓住了) |
| 7.9 单核回归(N=1,同一 scala) | `n1-r2/rd2`(gen `RD2AtomicXv6FastConfig` 0b…/`RD2AtomicBootConfig`,13 探针 fast+trace,M1 冻结 ELF) | **与 M1 closeout2 完全一致**:13/13 标记 ok、周期 Δ=+0、恢复后的控制台相同、13/13 COMMIT/TRAP 序列相同(`compare-fast/trace.txt` `fails=0`);R-BOOT 四门 `RBOOT_DONE fails=0`,九行与 M1 逐行相同 |
| 7.10 矩阵拒绝 | `n1-r2/refuse-*` | pipeline / 0 / 4 三者均在 elaboration 拒绝,消息含值(`unsupported CORE_IMPL=pipeline…`、`unsupported NUM_CORES=0…`、`unsupported NUM_CORES=4…`) |
| 7.11 单元回归 | `n1-r2/atomic-rerun`(原 CPU-A 27 场景,原版 score.py)、`n1-r2/dual-directed`(M2a 定向 11)、`n1-r2/dual-kill`(M2a kill 组 10) | **27/27、11/11、10/10** |
| 7.12 共享树 | `MANIFEST.md` | `fpga-zynq` 非 git 仓库;scala 树 sha256 与 M1 基线相同;02:00 起除 sbt 缓存外 0 个文件被修改 |

耗时:dual 生成 31–67 s、Verilator 构建 ~80 s、短程序 1–30 s、dual03 每 seed ~30 s、dual03 trace 363 s、dual07 58 s;n1 回归约 21 min;全部经 coord job(`mc-m2b-compile-check-1`、`mc-m2b-smoke1/2/3`、`mc-m2b-n1-regress`、`mc-m2b-suite`、`mc-m2b-round2`)。

## 8. 基线未解决项(沿用 M1 T1.4)

核级 ISA 套件 su(fails=9:`su08_satp_bare/su09_warl/su11_mip_sw`)、m(fails=6,含 misa 常量旧期望)、c(fails=16)在参考 RTL 与本 RTL 上同样失败(M1 已归类,RTL 未变),**继续列为基线未解决,不声称全 ISA 绿**;本包未重跑核级套件(RTL sha 与 M1 相同)。

## 9. 过程中的偏差与修正(如实记录)

| # | 事实 | 处理 |
|---|---|---|
| 1 | 首个 dual01 运行:hart 0 反复 `cause=4`(load 未对齐)且 trap 掉回 ROM 静默重启;事件流为空 | ① `BARRIER` 宏用 `tmp` 同时作地址与常量(`li tmp,n` 覆盖了地址)→ 常量改用 a6;② `start.S` 装默认 trap 向量 `trap_default`(hart 0 打印 `M2B-TRAP-FAIL` 退出 99),不再掉回 ROM;③ Verilator 的 `printf` 走 stderr,`run-dual.sh` 原本把 stderr 单独写文件——改为合流(与 M1 的 runner 一致) |
| 2 | 程序字符散落为 AT/RD2 行的前缀,`M2B-…-OK` 标记不成串 | `run-dual.sh` 生成 `console-clean.txt`:逐行恢复(带 trace 记号的行只留记号前字符),同 M1 `probe_console.py` 的方法;`events.txt` 提取不再锚定行首 |
| 3 | 判定器把 ROM 唤醒阶段的软中断算进 dual02/dual04 的程序阶段 | 以每 hart 首条 `0x80000000` COMMIT 为界,只计程序阶段 |
| 4 | 判定器对 dual06 要求"恰一次 RESET_APPLY、末 epoch [1,1]"——忽略了 host 装载期的首次复位(epoch 0→1) | 只判注入之后的事件,末 epoch [2,2] |
| 5 | 变异自测 m15 的 sed 误匹配 `nofence=`;`rej` 把运行目录传了两次 | 修正 sed 与参数;19/19 |
| 6 | 负向 `neg04_early`(hart 0 不等屏障)首轮**被接受**:两 hart 速度相同,hart 0 报告时 hart 1 也已退休 ≥1 M,而判定器只看 `retired1` | 判定器增加归并状态规则(报告中的两 hart 迭代数都必须为 ITER);负向改为 hart 1 工作量 2×,使早结束真实可见(`iter1=0`)——一个曾"不能失败"的负向被修成能失败 |
| 7 | **N=1 回归首轮不一致**:13 探针恢复控制台 `aWaits` 40→39,`ext04_sv39` 周期 +298、COMMIT 序列多 10 行(轮询循环多转 5 圈);ROM 首条指令退休 15→16 拍 | 原因是对齐 hold(`holdAll`)把 host 3 拍装载复位后的释放推迟 1–2 拍,单核下也生效;改为 `nHarts > 1` 才 elaboration 该逻辑(单核字节一致是接口要求);round 2 单核 13/13 控制台相同、周期 Δ=0、COMMIT 序列相同 |
| 8 | `MC1UnsupportedZeroConfig` 首轮拒绝但消息不含 `unsupported NUM_CORES=0`:`WithAtomicHub` 闭包在 SoC 检查前 elaborate,先以后端"名字非空"的 require 失败 | 在闭包内以同样措辞先行拒绝;round 2 三项拒绝消息均含值 |
| 9 | round 2 重生成的双核 Verilog 与 round 1 **不同**(1936/1198 行) | 逐行核对:全部是 `@[… .fir@NNN]` 源位置注释与 TL monitor 断言字串中的 `AtomicHub.scala:38→:42` 行号(hub 多了 4 行注释/require);剥去二者后 **0 行差异**;双核仿真器仍全部重建重跑(round 2),不依赖该结论 |
| 10 | 提交 b147091 比证据用的私有 common 多 5 行注释(`AtomicBackend.scala` RESV 诊断行措辞,Codex 对 M2a 的备注,允许不另跑回归) | `runs/common-vs-commit.diff` 记录,0 行非注释 |
| 11 | 负向程序 `neg01`(hart 1 不到达)只能由超时/无 host 结果拒绝 | 如实记:超时是拒绝的一种,不是"检出机制";另三个负向由具体规则拒绝 |
| 12 | dual03 的 tracing 运行中共享字 LR/SC 失败为 0(该时序恰无竞争) | 如实报告;FAST 的 10 个时序中 6 个出现竞争失败(§7.3),SC 语义在两种情形下都正确 |
| 13 | **Codex 复审①**:判定器把 drain 检查整体放在 `if … and ra:` 内,缺 RESET_APPLY 时不报错、直接通过 | 重写:每个必需事件的存在与唯一性无条件核验,再核时序(DRAIN_DONE→apply→SAFE→release),释放后无陈旧响应;变异自测证明删 RESET_APPLY/SAFE、提前 apply/释放各按原因拒绝 |
| 14 | **Codex 复审②**:"已应答 DRAM 写 ≤ 含 host 的 AXI 写总数"证明不了不丢已提交写(host 装载写掩盖缺失;被 drain 丢弃响应的写不在计数内;WLAST≠成功 B;`seq` 字典跨 reset 覆盖) | 改为逐笔绑定:请求 `(hart, epoch, seq)` ↔ AXI AW/W/B(地址、lane、数据、resp=0、在 RESP/DRAIN_DONE 之前),恰一次;CPU 专用区无多余 AXI 写;程序在重装载后读回映像外 scratch 的幸存前缀并与 hold 前发出的写数精确相等;变异:丢一笔/改数据/改地址/丢在途笔/重复一笔/早 DRAIN_DONE/陈旧响应/篡改幸存数均检出 |
| 15 | **我自己复核发现**:交付时的 dual06 记录里,注入(6004)落在 host 装载期,两 hart 在途的是 ROM 的取指,不是写——"两真核有在途访问"成立,但不是任务要的写在途;runner 也没保留 AXI(EVA)行 | 旧记录用新规则重评为 FAIL 并保留;dual06 改为 v2(映像外 scratch、epoch 字、幸存前缀报告),注入改瞄写流(46000),runner 保留 EVA 行;新记录 `runs/drain2` 通过闭合规则 |

## 10. 状态

交付物:工作树 `worktrees/mc-dual-core` 提交 **b147091**(基于 33c4864;未推送、未打 tag);`experiments/multicore/m2b/{REPORT,RESULTS,MANIFEST}.md`、`gen/`、`progs/`、`tests/`、`tools/`、`runs/`。未做(按任务书):双核 xv6、Vivado/综合、板/串口、host 协议改动、旧产物清理。未确认项 U1/U2 已由实测转为已确认(§6),PLIC S 态地址的实际落点记为 xv6 阶段注意事项。首轮 OPEN `claude-mc-m2b-real-dual-ready` 获部分认可;复审 `codex-mc-m2b-drain-closeout` 的两项已闭合(§9-13/14/15,§7.6),未重跑长锁/长期进度/单核全套(Codex 明示不需要;这些记录与 scala 提交 b147091 不变),OPEN `claude-mc-m2b-drain-fixed-ready`。
