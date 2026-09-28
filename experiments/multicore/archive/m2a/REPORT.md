# MC-M2a — 多 hart 原子后端(dual-backend)交付报告

任务:`.coord/proposals/codex-mc-m2a-dual-backend.md`(已 ack)。工作树 `worktrees/mc-dual-backend`(分支 `mc-dual-backend`,基于 MC-M1 验收提交 `bcf403e`)。**未推送、未打 tag、未发布;未触碰板卡/串口/复位/烧写;未运行 Vivado;未改 xv6/host;未写共享 `fpga-zynq` 树(它不是 git 仓库,证据见 §7.9;§9-4 记一次误入与清理)。**

## 1. 范围与结论

- 后端 `AtomicBackend` 从"一个 CPU 源区间 + 一份 reservation"改为 **按精确 client 名绑定 N 个 hart,每 hart 一份 reservation、一条 sideband**;桥 `RD2BridgeV2` 得到 `clientName`/`hartId` 参数;单核 RD2 路径保持默认值(`Seq("teaching-phys")`,`io.sb(0)`),**产品级双核配置仍不受支持**(M0 裁决,本包不放开)。
- 新增双 hart 单元 harness `DualAtomicHarness`(两桥 + 两外部写源 + 可选第三写源 + 可交换接线顺序 + 两侧 delayer/背压 + 对齐 apply 的 drain),定向 11 项、随机 10 seed(每 seed ≥ 12,700 完成事务)、拓扑变体 3 项、负向 8 项(全部按声明签名拒绝;每个负向有无故障孪生正向)、精确名绑定的 3 个 elaboration 拒绝配置。
- 多 hart oracle `tests/score2.py`:按 CPU_SOURCE 公告表(非 DUT 自己的 `cpu=`/`hart=` 分类,后者被核对)把 TileLink 源绑定到 hart,以**实际接受顺序**推导每笔请求的 TL 映射、AMO 新旧值、SC 判定、跨 hart 的 reservation kill、内存镜像、D 路由与 CPU 响应,再与 DUT 逐项比对;含 C7.1 对齐 drain 规则。变异自测 32/32(oracle 规则覆盖的证据,不是任何硬件场景的证明)+ drain 变异自测 8/8(真实 d11 日志)。**Codex 复审(`codex-mc-m2a-simultaneous-kill-fix`)发现 `nKill` 同拍多预约清除漏计,已修并补 d13–d17,见 §7.10 与 §9-15…17。**
- 单核回归:从本工作树 scala 重生成 `RD2AtomicXv6FastConfig`/`RD2AtomicBootConfig`,用 M1 冻结程序集(字节一致)跑 13 个短探针(boot/ext 含 A 与 Sv39),与 M1 `closeout2-after-*` 比较;R-BOOT 四门在 tracing 仿真器上重跑,与 M1 逐行比较。原 CPU-A 27 场景 + 其 score 自测用**原版 `score.py`**(只读)重跑。
- 结果汇总见 §7 与 `RESULTS.md`;构建输入见 `MANIFEST.md`。

## 2. 设计(工作树 diff,`git diff bcf403e -- soc/`)

### 2.1 `AtomicBackend.scala`(+210/−?)

- 签名:`AtomicBackend(faultReadErrWrites, faultNoKill, faultWrongSource, cpuClientNames: Seq[String] = Seq("teaching-phys"), dramRegion, trace, faultNoCrossKill, faultSwapSideband, faultSwapDSource, faultAmoInterleave)`;`io.sb = Flipped(Vec(n, AtomicSideband))`,slot i = `cpuClientNames(i)`。
- **绑定(D4,elaboration 期 `require`)**:名字非空且唯一;每个名字在 inner edge 上**恰好**解析为一个 client;所有以 `teaching-phys` 开头却未被绑定的 client → 拒绝(不许"多出来的 hart 被当外部源");各 hart 源区间两两不重叠。不排序、不按前缀猜。启动时打印 `CPU_SOURCE hart= lo= hi= clients= harts=`(公告的是真实区间;`faultWrongSource` 只改分类用的区间,故 oracle 可抓到)。
- **每 hart 状态**:`markQ(h)`(LR/SC 标记队列)、`resvValid(h)/resvWord(h)`(8 字节粒度)、`curHart/curIsCpu`(当前被接受事务的归属)。
- **kill 规则(D3)**:`cpu-write`(本 hart 的普通写/AMO 覆盖自己的 reservation)、`other-hart-write`(其它 hart 的写/AMO 覆盖)、`external-write`(非 CPU 源写覆盖;`faultNoKill` 关闭它)、`sc-write`(**成功的 SC 是一次写**,杀掉其它 hart 重叠的 reservation;`faultNoCrossKill` 关闭它)、`core-clear`(核侧 `resvClear`:trap 等)、`lr-error`(LR 返回错误)。失败的 SC 不写、只清自己。
- **串行 FSM** 不变(`sIdle/sPass/sPassD/sGet/sGetD/sPut/sPutD/sResp/sScFail`),新增 `sSneak/sSneakD` 仅供负向 `faultAmoInterleave`(AMO 的 Get 与 Put 之间放进一笔别的写);`faultSwapDSource` 把合成的 D(AMO 结果、失败 SC)发给**另一个** hart 的 source;`faultSwapSideband` 把 sideband slot 交叉(`slot(h)=h^1`)。
- **`nKill` 语义(复审修订)**:本拍被清除的**有效预约数**,同一 hart 同拍多原因最多计一次(一个 hart 只有一份预约)。各原因只置该 hart 的 `killIntent(h)`,`nKill := nKill + PopCount(killIntent)` 每拍加一次;SC 消费自己的预约(成功或失败)不是 kill、不计;`RESV kill` 诊断行由**每个**在预约有效时触发的原因各打一行——同 hart 同拍两个原因(d17:trap + 外部写)打**两行**,计数语义只由 popcount(硬件)与 oracle 自身状态给出,诊断行不是计数(Codex 验收备注,随 M2b 包更正,注释见 mc-dual-core 的 `AtomicBackend.scala`)。修订前 `killResv` 循环内 `nKill := nKill + 1.U`,两 hart 同拍清除时 last-connect 只加 1(§7.10 用旧后端复现)。
- 事件:`A_ACC ... cpu= hart=(255=外部)`、`RESV set/kill hart= why=`、`SC_OK/SC_FAIL hart=`、`AMO_START hart=`、`INTERLEAVE src=`。

### 2.2 `RD2BridgeV2.scala`

`clientName: String = "teaching-phys", hartId: Int = 0`;`node = makeClientNode(clientName, IdRange(0,1))`;`CPU_REQ/CPU_RESP` 行带 `hart=`;`faultMode 11`:已提供的 TL A 在未被接受的下一拍撤回一拍(TileLink 侧不可撤回规则的负向)。

### 2.3 接线点

`RD2Soc.scala:219`、`AtomicSoc.scala:66`、`AtomicTest.scala:200`:`io.sb(0) <> ...`;`AtomicHub.WithAtomicHub(..., cpuClientNames = Seq("teaching-phys"), fNoCrossKill, fSwapSideband, fSwapDSource, fAmoInterleave)`。单核 RD2 生成物只应差在这些参数的默认值(§7.5 用 M1 的比较器验证行为不变)。

### 2.4 `AtomicTest.scala`

`V2Driver(steps, respStall, respRandom, hartId, withdraw)`(`withdraw`:桥忙时给一拍伪 valid 再撤回的负向);`CPU_TRAP/CPU_HELD hart=`;步索引 16 位(随机脚本 6000 步);新步 `until(c)`(kind 8):在首个 `cyc ≥ c` 的周期完成,两 driver 用同一 `until` 即可让下一步(trap)精确同拍。

### 2.5 `DualAtomicTest.scala`(新)

`DualParams`(两 hart 脚本、两外部写源、可选第三写源 `extra`、`swapOrder`、latency/aStall/mgrDStall/delayQ、每 hart 响应背压、`drainAt/resetLen`、全部故障旋钮、`backendNames`、超时)。`DualAtomicHarness`:桥名 `teaching-phys-0/1`;tap 放在**桥侧**(delayer 之前)监视 phys 与 TL 两侧的撤回/载荷改变 → `VIOLATION ... hart=`;drain 按 **C7.1** 建模——`softReset` 保持到两桥都 `applying`(`APPLYING_ALL`),`RESTART_SAFE = applying_all && !pendingWork`,任何 hart 不得先于对齐点脱离复位;`FINISHED cpuResp= cpuResp0= cpuResp1= amo= scOk= scFail= kills= bridgeIllegal= tlErr=`。场景 `DualScen.d1…d12`、`randomScript(seed,hart,n,pauses)`/`randomPuts(seed,who,n,span)`(elaboration 期 `scala.util.Random`,可复现);配置 `Dual01…Dual12*Config`、`DualRnd1..10Config`、`DualRnd1{Swap,Extra,SwapExtra}Config`、`DualNeg*Config`(8)、`DualRefuse{Missing,Stray,Dup}Config`(3)。

## 3. Oracle:`tests/score2.py`(多 hart 回放)

- 输入:仿真 `run.log` 的 `AT <cyc> <TAG> k=v` 事件。**绑定**:`(hart, txid)`;TL 源→hart 由 `CPU_SOURCE` 表决定;DUT 打印的 `cpu=/hart=` 只被核对。
- 对每笔 `CPU_REQ`:按 V2 契约独立判合法性(对齐、lane、种类、原子仅限 DRAM 且 size∈{2,3});合法者预期恰好一笔 A、恰好一笔 D(源必须等于被接受事务的源 → 否则"misrouted response")、恰好一笔在 D 之后的 `CPU_RESP`(txid、数据 lane、err、scFail 逐项),非法者不得产生 TL 事务且必须 err。
- `A_ACC` 时以**接受顺序**推导:TL opcode/param/操作数/lane 必须等于请求的映射(AMO 码→`Arithmetic/Logical`+param);LR 置本 hart reservation;SC 按本 hart reservation 判定,成功 → 写内存、杀其它 hart 重叠 reservation,失败 → 不写、只清自己;普通写/AMO/外部写/多拍写杀所有其它重叠 reservation(本 hart 自己的也清);AMO 的 Put 数据 = f(op, param, old, operand)(有符号/无符号 min/max、add、逻辑、swap,.W 按 lane);读错误后不得有 Put;Get 与 Put 之间**任何**接受(含 `INTERLEAVE` 事件)都拒绝;后端一次只许一笔未完成(第二笔 A → "serialisation broken")。
- 外部源:`EXT_A` 逐拍计数,必须被后端接受(`A_ACC`/`A_BEAT`)且收尾时计数归零;后端接受了没人提供的外部 A → 拒绝。
- 结束:无未闭合事务、无未完成 AMO、每 hart 都有 `CPU_SOURCE`、`MGR_WRITE` 序列 == 模型写序列(逐笔地址/mask/新值)、`FINISHED` 计数与模型一致(scOk/scFail/amo 相等,**kills 精确相等**——模型从自身状态计『被清除的有效预约数』:本/他 hart 写、外部写、多拍写、他 hart 成功的 SC、核侧 resvClear(trap)、LR 错误;SC 消费自己的预约不计——修订前为 kills ≥ 模型,见 §9-15;bridgeIllegal 相等,每 hart cpuResp 相等)。`--expect-kills/--expect-scok/--expect-scfail` 要求精确值。
- **drain(C7.1)**:每 hart `HOLD_ASSERT → DRAIN_DONE → HOLD_RELEASE`;hold 期间发出的新请求不得被接受(`CPU_REQ` 在 hold 内即拒绝);hold 期间被接受的只能是 hold 前已发出的请求,它必须由 drain 丢弃(`DRAIN_DISCARD`)而不得作为 `CPU_RESP` 交付,且丢弃不得早于其 D(已接受的写不许被复位丢掉);`DRAIN_DONE` 之后该 hart 不得再有 D;**任何 hart 的 release 不得早于所有 hart 的 DRAIN_DONE 与 `APPLYING_ALL`**;必须出现 `RESTART_SAFE`。
- 公平性统计:每 hart `wait<=`(CPU_REQ→A_ACC 最大等待)与 `turn<=`(A_ACC→D 最大周转),`--dmax` 给出声明的下游上限并报告比值(有限测试,不是无条件证明)。
- 自测:`tests/score2-selftest.sh`(两份合成最小双 hart 日志:基线 + 单规则变异各按其原因拒绝,含 kills 多计/少计、trap 清除计数、精确值不达 → 32/32,`runs/score2-selftest.txt`);`tests/score2-drain-selftest.sh`(真实 d11 日志 + 7 个 drain 变异 → 8/8,`runs/score2-drain-selftest.txt`)。两者都在 chipyard 的 python 3.10 下运行(§9 记录一次 f-string 兼容修正)。

## 4. 入口与预算

```bash
M2=/home/engineer/fpga/experiments/multicore/m2a
bash $M2/gen/prepare-common.sh worktrees/mc-dual-backend/soc/scala/teaching $M2/gen/common-dual   # 私有 common(共享树不写)
TOPPROJ=<pkg> bash $M2/gen/gen.sh <TOP> <Config> $M2/gen/common-dual <fresh out>                   # 绝对路径,否则拒绝
bash $M2/tests/dual-run.sh <common> <outroot> <name> <Config> <ntx> <lat> <astall> <mgrd> <resp> <dq01> [score2 flags]
bash $M2/tests/dual-all.sh <outroot> directed|random|topo|neg|all
bash $M2/tests/atomic-rerun.sh <outroot>          # 原 CPU-A 27 场景 + score 自测,原版 score.py
bash $M2/tests/rd2-regress.sh <outroot> all       # gen×2 → 探针(fast/trace,M1 冻结 ELF)→ 比较 → R-BOOT
bash $M2/tests/m2a-pipeline.sh $M2/runs           # topo → neg → atomic-rerun → rd2,一个 coord job
bash $M2/tools/manifest.sh > $M2/MANIFEST.md; bash $M2/tools/collect-results.sh > $M2/RESULTS.md
```

周期预算由声明参数计算(`dual-run.sh`):`bound = 3·(lat+aStall+mgrD+12·dq+8)+resp+6`,`+max-cycles = ntx·bound·1.5`,elaboration 期 `UnitTest(timeout)` 同量级;超时是结果不是重试。所有 >2 min 的工作经 `./coord job start`,一次一个重活,Verilator `-j 4`。

## 5. 约束遵守

无 push/tag/release;无板卡/串口/复位/烧写;无 Vivado;无 xv6/host 改动;原 `ips-*` 工作树、冻结镜像、用户磁盘、共享 `teaching-cpu-work/fpga-zynq` 未写(§9-4 记录一次由相对路径导致的误入目录并已清除;该树不是 git 仓库,『未写』的证据是 §7.9 的 sha256 基线与 mtime 扫描);/tmp 未清理(`/tmp/b0simrun`、`/tmp/claude-1000`、`/tmp/cli1`、`~/fpga/sim-scratch-archive` 未动);新结果全部在新目录;历史证据(`runs/dual-directed` 首轮含 3 个未达 floor 的运行、`runs/smoke/*`)保留。

## 6. 场景与 floor(为什么这样断言)

定向场景的 floor 断言"预期交错确实发生了"(oracle 从实际顺序推真值,floor 防止一个"什么都没撞上"的运行冒充通过):d01 h0 SC 成功 & h1 SC 失败 & ≥1 kill;d02 h0 SC 失败 & kill;d03 两 hart 各成功一次;d05 h0(trap)失败、h1 成功;d06 外部写 ≥1、kill、h0 失败、h1 成功;d07 单字节部分写 kill;d08 h1 无 reservation 的 SC 失败且 h0 成功;d09 读错误拒绝 ≥1、只写错误拒绝 ≥1、非法 ≥3、SC 失败 ≥3、成功 ≥3、AMO 2(ROM/MMIO 上的 AMO 非法,不计);d10 AMO ≥27;d11 `--drain --min-drained 2`(两 hart 都有在途);d12 AMO ≥60 且 `--dmax 20` 报告最长等待。d13–d17(复审新增,正常与 swap 拓扑各一):d13 外部普通写清两预约、d14 外部 partial 写、d15 同拍双 trap、d16 一次双拍写覆盖 X 与 Y 两 granule——各 `--expect-kills 2 --expect-scfail 2 --expect-scok 0`(精确:两预约清前有效由 oracle 状态保证,清后两 SC 必失败);d17 同 hart 同拍双原因(trap + 外部写同址)`--expect-kills 1 --expect-scfail 1 --expect-scok 1`(另一 hart 的预约必须幸存),runner 另核对 `CPU_TRAP hart=0` 与外部 `A_ACC` 同周期作为激活证据。随机:每 seed `--min-tx 10000`、scOk ≥50、scFail ≥100、AMO ≥500、kills ≥50、外部 ≥100。**判定边界(与 runner 的实际行为一致)**:正向必须仿真正常退出(exit 0、有 `FINISHED`)**且** oracle 闭合无 fail;负向只按**声明的检查**判"拒绝"——声明的检查可以是 oracle 的一条 fail、后端自身的 `assert`、或 inner edge 的 TLMonitor 断言,后两者会提前终止仿真(无 `FINISHED`),这是被允许的,但必须同时满足:签名匹配、有激活证据(该场景的无故障孪生在正向组通过,即场景确实到达被检查的事件)、且拒绝原因是声明的那一条;未声明的崩溃、超时或无 FINISHED **不算**检出。

## 7. 结果(判定摘要;逐行见 `RESULTS.md`,日志见 `runs/`)

| 组 | 入口 / 目录 | 结果 |
|---|---|---|
| 7.1 定向 11 项(最终轮) | `dual-all.sh directed` → `runs/dual-directed-final`,`runs/dual-directed-final.log` | **11/11 通过**(sim exit 0、score 0、floor 全达)。d12 公平:`--dmax 20`,h0(连续流)最长等待 28、h1(间歇)13,turn ≤25;d11:两 hart 各 1 笔在途被 drain 丢弃(`drained=2`),`APPLYING_ALL`/`RESTART_SAFE` 在两侧 DRAIN_DONE 之后,两 hart 同拍释放(287) |
| 7.2 随机 10 seed | `dual-all.sh random` → `runs/dual-random`,`runs/dual-random.log` | **10/10 通过**;每 seed 完成事务 12,736–12,821(≥10,000),AMO 2,335–2,458,scOk 135–180,scFail 1,696–1,833,kills 911–943,外部 1,500,`MGR_WRITE` 序列与模型逐笔相等。最长等待:无 delayer 的偶数 seed h0/h1 ≤ 22–50 周期(声明 Dmax 15–21 的 1–2.5 倍:一笔请求最多等另一 hart 的一个 AMO 三趟);奇数 seed(两侧 `TLDelayer(0.25)`)≤ 260–893——由随机门控的几何尾部决定,不在 Dmax 声明内,如实报告、不判定 |
| 7.3 拓扑变体 | `runs/dual-topo` | **3/3**:桥接线顺序交换(源区间随之变化,`CPU_SOURCE` 公告 hart0 lo=2 / hart1 lo=3 反转)、第三外部写源(ext 1,875)、两者同时,结果同 seed 1 |
| 7.4 负向 8 项(最终轮) | `runs/dual-neg-final`,`runs/dual-neg-final.log` | **8/8 按声明检查拒绝**:no-cross-kill → `SC result scfail=0, model says 1`;swap-sideband → oracle `hart 1 txid=1 is a lr but the backend classified kind=0` + 后端断言 `mark pushed while one is pending`;swap-dsource → inner edge TLMonitor `'D' channel acknowledged for nothing inflight`;interleave → `admitted a write between an AMO's halves`;tl-withdraw → `VIOLATION tl A withdrawn hart=0`;phys-withdraw → `VIOLATION phys request withdrawn hart=0`(激活修正后,§9-13);wrong-src → `classified source 3 cpu=0, the announced table says hart=0`;no-kill → `SC result scfail=0, model says 1`。每个负向的无故障孪生(d2、d5、d10、rnd3 小样、d10、d1、d1、d6)在 7.1/7.2 通过 |
| 7.5 精确名绑定拒绝 | `runs/refuse/*`,`runs/final.log` | **3/3 在 elaboration 拒绝**:缺名(`'teaching-phys-9' must resolve to exactly one client ... found 0`)、未绑定的 hart-like client(`hart-like clients present but not bound: teaching-phys-1`)、重名(`must be non-empty and unique`) |
| 7.6 原 CPU-A 27 场景 | `atomic-rerun.sh` → `runs/atomic-rerun`,`runs/atomic-rerun.log` | **27/27**(`infra=0 score_fails=0`,原版 `score.py`;其 14 变异自测 `fails=0`);无不适用项(§8) |
| 7.7 单核 RD2 回归 | `rd2-regress.sh all` → `runs/rd2`,`runs/rd2.log` | 生成 `RD2AtomicXv6FastConfig`(dfaf5182)与 `RD2AtomicBootConfig`(842c60c3);13 探针(boot01–04、boot11_sv39、boot12_amo、cache01_smc、ext01_m、ext02_c、ext04_sv39、hello、tlb01/02)fast 与 trace 各 `fails=0`;与 M1 `closeout2-after-*` 比较:程序整文件与加载身份一致(13/13)、RTL 一致(66fa6703)、**13/13 周期 Δ=+0、13/13 COMMIT/TRAP 序列相同**(`compare-fast.txt`/`compare-trace.txt`,`COMPARE fails=0`);R-BOOT 四门 `RBOOT_DONE fails=0 infra=0`,九条门行与 M1 `rboot-after.log` 逐行相同(`rboot-diff.txt` 空) |
| 7.8 判定器自测 | `runs/checker-selftest.txt`、`runs/score2-selftest.txt`、`runs/score2-drain-selftest.txt` | 16/16、26/26、8/8 |
| 7.9 共享树 | `MANIFEST.md`;`find teaching-cpu-work/fpga-zynq -newermt '2026-09-26 21:00' -type f` | `fpga-zynq` **不是 git 仓库**(无 `.git`,`git status` 不可用);证据:① `common/src/main/scala` 全树 sha256 与 M1 基线 `m1/gen/shared-scala-before.sha256` 相同;② 自 M2a 开始(21:00)起,树内被修改的文件只有 `rocket-chip/*/target/`、`project/` 下的 sbt 编译缓存(每次生成都会写,与 M1/CPU-A 相同),其它为 0;③ 误入的 `simulation/experiments/` 已不存在;私有 common 的 scala == 工作树 |

| 7.10 同拍多预约清除(复审) | `dual-all.sh kill` → `runs/kill-new`,`runs/kill-new.log`;旧后端复现 `kill-repro-old.sh` → `runs/kill-old`(`gen/common-old` = 私有 common + d9c4008 的 `AtomicBackend.scala`;`old-vs-new.txt` 记两版 sha 与 diff) | **修后 10/10**(d13–d17 × 两拓扑,kills/scok/scfail 全部精确;两条 `RESV kill` 行同在 cycle 81;d17 的 trap 与外部 A_ACC 同在 81,幸存 hart 的 SC 成功)。**旧后端 8/8 双预约用例复现漏计**:`FINISHED kills=1`,oracle `the backend counted kills=1, the model counted 2 cleared reservation(s)`;d17 两例旧后端亦为 1(单预约,无差别,作为『必须保持 1』的对照) |
| 7.11 修后全量重跑 | `m2a-kill-pipeline.sh` → `runs/{dual-directed-fix,dual-random-fix,dual-topo-fix,dual-neg-fix,atomic-rerun-fix,rd2-fix}` 及同名 `.log` | **全部通过,与修前同口径**:定向 11/11、随机 10/10(kills 现为精确相等:seed 1–10 的 DUT nKill = 模型 995–1105;修前 DUT 951–1043 落在旧模型下界之上、掩盖了同拍漏计)、拓扑 3/3、负向 8/8 按声明检查拒绝(理由与 §7.4 相同)、原 CPU-A 27/27(原版 score.py,自测 fails=0)、单核 RD2:重生成 `RD2AtomicXv6FastConfig`(b4a46e14)/`RD2AtomicBootConfig`(25090a64),13 探针 fast+trace `fails=0`,与 M1 closeout2 比较 13/13 周期 Δ=+0、13/13 COMMIT/TRAP 相同,R-BOOT 四门九行与 M1 逐行相同。共享树见 7.9 |

耗时:定向/负向每项 gen+verilate 15–20 s、仿真 <1 s;随机每 seed FIRRTL 90–135 s(6000 步向量)、仿真 2–3 s;CPU-A 重跑 27 项约 10 min;RD2 回归(2 次生成 + 2 个仿真器 + 26 次探针 + R-BOOT)约 5 min。全部经 `./coord job start`(`mc-m2a-compile-check-*`、`mc-m2a-smoke-*`、`mc-m2a-dual-directed`、`mc-m2a-dual-random`、`mc-m2a-pipeline`、`mc-m2a-final`),日志 `.coord/jobs/logs/`,副本 `runs/*.log`。

## 8. 不适用项

原 CPU-A 的 27 个场景(单元 21 + SoC 拓扑 6)**全部适用**,均以原版 `score.py` 重跑(`runs/atomic-rerun`,`ATOMIC_RERUN_DONE scenarios=27 infra=0 score_fails=0`;其 14 变异自测 `fails=0`)。它们经 `AtomicTest.scala`/`AtomicSoc.scala` 的单桥 harness,后端以默认 `Seq("teaching-phys")` 绑定 1 个 hart(`io.sb(0)`);事件行多出的 `hart=` 字段被原 scorer 的 `k=v` 解析自然忽略,`CPU_SOURCE` 仍带 `lo=/hi=`。无删减、无静默跳过。

## 9. 过程中的偏差与修正(如实记录)

| # | 事实 | 处理 |
|---|---|---|
| 1 | 首轮 `common-dual` 是在 `DualAtomicTest.scala`/`V2Driver` 改动之前拷贝的,编译检查 `mc-m2a-compile-check` 失败 | 从当前工作树重新同步 scala 后再编(此后每次 scala 改动都先同步再生成;pipeline 运行期间**不**同步,避免改变正在记录的输入) |
| 2 | `object DualScen` 内 `wait(n)` 解析为 `AnyRef.wait`(Unit),两处类型错误 | 场景助手改名 `pause(n)` |
| 3 | 单元测试 top `TestHarness` 在 `freechips.rocketchip.unittest` 包(与 CPU-A 相同),不是 `teaching`/`zynq` | `gen.sh` 增加 `TOPPROJ` 覆盖(默认 `teaching`) |
| 4 | **`compile-check-4/5` 给 `gen.sh` 传了相对路径**;make 的 cwd 是 `fpga-zynq/simulation`,于是在共享树里生成了 `simulation/experiments/multicore/m2a/gen/common-dual/lib/`(jar 拷贝 + rocketchip.stamp,共享树其它部分未动) | 删除该误入目录(我自己 21:25 的产物),目录已不存在;`gen.sh` 现拒绝相对路径(已验证拒绝退出 2);coord log 已记 |
| 5 | `score2.py` 摘要行用了同引号嵌套 f-string,chipyard 环境是 python 3.10,在 job 里 SyntaxError(自测在系统 python 下曾通过) | 改写;自测改在 chipyard python 下运行(26/26) |
| 6 | d06 的 DMA 写在 cycle 200,晚于 hart 0 的 SC(~100),预期交错未发生(floor 抓住:kill 0、h0 scfail 0) | 改为 cycle 50;`runs/dual-directed`(首轮)保留,重跑记录在 `runs/smoke/d06-dma-kills` 与最终 `runs/dual-directed-final` |
| 7 | d09 floor `--min-amo 3` 错:ROM/MMIO 上的 AMO 是非法请求不进后端,只有 2 个 AMO 进后端 | floor 改 2 |
| 8 | d11 首轮:hart 1 在 hart 0 还在 drain 时就被释放(266 vs 284)——harness 没有建模 C7.1 的 SoC 级对齐;同时 oracle 的单 hart 规则"hold 期间不得接受"对双 hart 过严(hold 前已提供的 A 在另一 hart 事务完成后才被接受是合法的,TileLink 不许撤回) | harness:`softReset` 保持到 `APPLYING_ALL`;oracle:hold 内只允许 hold 前已发出的请求被接受且必须被 drain 丢弃、不得作为响应交付、任何 hart 不得早于全部 DRAIN_DONE/APPLYING_ALL 释放;新增 drain 变异自测 8/8 |
| 9 | 随机 seed 1 起跑即 `$fatal`:TLMonitor "PutFull address not aligned to size"——`randomPuts` 在 4 字节对齐的 X4/Y4 发 size-3 Put、在 Y(非 16 对齐)发双拍 Put | 生成器按对齐选 size/mask;为快速复现新增 `DualRnd1SmokeConfig`(n=300);停掉当时的 random job(coord log 已记)以免每 seed 白烧 2 min FIRRTL |
| 10 | 随机小样本:两 hart 同拍 `VIOLATION tl A withdrawn` 周期性出现——tap 放在 delayer 的 xbar 侧,看到的是 TLDelayer 合法的随机 valid 门控 | tap 移到桥侧(delayer 之前) |
| 11 | 随机 floor `--min-illegal 1` 不可达(随机脚本不生成非法请求),`--min-scok 100` 偏紧 | 去掉 illegal floor,scOk floor 50(实际每 seed 135–180) |
| 12 | 负向 `neg-swap-sideband`/`neg-swap-dsource` 未按我原先声明的签名检出,而是被后端自身断言(`mark pushed while one is pending`,前面还有 oracle 的"hart 1 的 LR 被分类为 kind=0")与 inner edge 的 TLMonitor(`'D' channel acknowledged for nothing inflight`)拦下 | 声明签名改为这些实际的检查(都是真实检查,不是崩溃/超时);首轮 `runs/dual-neg` 保留,最终在 `runs/dual-neg-final` |
| 13 | 负向 `neg-phys-withdraw` **未激活**:桥在空闲时同拍接受请求,driver 的"未被接受后撤回"永远不触发,运行以 score=0 通过——一个不能失败的负向 | driver 故障改为"桥忙时给一拍伪 valid 再撤回";最终轮验证其被 `VIOLATION phys request withdrawn` 拒绝 |
| 15 | **Codex 复审发现**:`killResv` 循环内 `nKill := nKill + 1.U`,两 hart 同拍被清除时只计 1;我的 oracle 用 `kills ≥ 模型`,且模型不计 core-clear/lr-error,DUT 的这两项多计**掩盖**了漏计——随机 10 seed 全绿并不覆盖该交错 | 后端改 `killIntent` + `PopCount`;oracle 改精确相等并计入全部清除原因;新增 d13–d17 先在旧后端复现(8/8)再在新后端通过(10/10);自测加 kills 多计/少计/trap 计数变异 |
| 16 | 原 §6『崩溃/无 FINISHED 不算检出』与 §7.4 两个断言终止的负向措辞不一致 | §6 改为与 runner 一致的边界:正向须正常退出+闭合;声明为断言的负向可提前终止但须签名+激活证据+无故障孪生;未声明的 crash/timeout 仍拒绝 |
| 17 | 报告中『26/26 自测』曾与硬件结论并列 | 明示为 oracle 变异覆盖证据,不是硬件场景证明 |
| 18 | 报告与提案曾写『共享树 git 状态 0 路径』——`fpga-zynq` 没有 `.git`,该命令输出为空只是因为 `git` 报错,结论是空洞的 | 改为可证的证据(§7.9:scala 树 sha256 基线相同 + 21:00 起除 sbt 缓存外 0 个文件被修改 + 误入目录不存在);首个提案 `claude-mc-m2a-dual-backend-ready` 中的同一措辞以此更正 |
| 14 | 随机场景外部写源的时间跨度 `n·40` 周期(~240k)长于两 hart 脚本用时,后半段只有外部流量 | 如实报告;不改(每 seed 的 CPU/外部重叠段已 ≥ 数千笔) |

## 10. 状态

交付物:工作树 `worktrees/mc-dual-backend` 提交 **d9c4008**(M2a)+ **33c4864**(复审修正 nKill 计数、`until` 步、d13–d17;**未推送、未打 tag**);`experiments/multicore/m2a/{REPORT,RESULTS,MANIFEST}.md`、`gen/`、`tests/`、`tools/`、`runs/`。未做:产品级双核 SoC 配置(仍按 M0 裁决不支持,不在本包)、长 xv6(任务书明示无需)、板上任何操作。复审任务 `codex-mc-m2a-simultaneous-kill-fix` 四项(语义修正、定向反例含两拓扑、旧版复现→修后通过且未放宽 oracle、受影响回归重跑)与报告边界措辞均已完成;OPEN `claude-mc-m2a-kill-fixed-ready`,等待 Codex 验收。
