# MC-M4 — 双核 40 MHz 离线实现与部署准备:交付报告

任务:`.coord/proposals/codex-mc-m4-offline-build.md`(已 ack)。硬件工作树 `worktrees/mc-dual-xv6` 提交 **565d33f**(基于 M3 验收提交 99b53b1,只加 `RD2DualBoardConfig` 与一处注释);构建目录 `experiments/multicore/m4/build/attempt-1`;软件隔离副本 `experiments/multicore/m4/sw/xv6`(= M3 树 + 编译开关)。**只做离线准备:未访问板/JTAG/串口,未烧写,未推送,未改单核镜像、共享 Vivado 环境或共享 checkout;不代表已获烧写许可。**

## 1. 结论(摘要)

- **双核 RD2ZynqTop(真实板级顶层,不是带计数器的 harness)在 40 MHz 收敛**:route 后 WNS +0.396 ns / TNS 0,WHS +0.035 ns / THS 0,pulse width 满足,`check_timing` 12 类全 0,无跨时钟路径,时钟集与基线相同;DRC/方法学告警与单核基线逐条相同(均在 PS 侧 AXI 互连内);冻结判定器 `check-impl-reports.py` 在四项人工声明后 **PASS**。一次构建成功(Vivado 全流程 667 s),无修正重跑,未降频、未改架构。
- **资源(route 后)**:22,631 LUT(42.5 %)/ 11,181 FF(10.5 %)/ LUTRAM 1,265 / BRAM 0 / DSP 0,对比单核 cache 基线 14,554 / 7,011:+8,077 LUT、+4,170 FF;每核 `core` 7.4k LUT 与单核相同,增量 = 第二核 + 第二桥 + 双端口 crossbar/总线 + CLINT/PLIC 第二上下文;共享后端 1,123 LUT(基线 1,129)。
- **构成逐项记录**(§3):nHarts = 2(`HART_ID` 0/1 各一),每核 fetch32 + 8 项 TLB + 1 KiB I-cache,无 D-cache,一个共享串行原子后端,每 hart CLINT(msip/mtimecmp),PLIC 每 hart 一个 M 态上下文、无设备中断源(内核不触碰);单核配置保留可用;40 MHz 由与基线相同的 MMCM/约束给出。
- **部署包**(`deploy/`):bit + 经自检转换器得到的 payload(`43e5b414…`)+ 部署内核 128 MiB + 部署磁盘 + 已验收 host 二进制,兼容性(HP0 翻译、保留内存、DT、磁盘路径、TSI 协议、ROM)逐项核对;未来上板步骤、冷启动、串口交还门禁、单核恢复写在 `deploy/README.md`。**只是离线准备,无烧写许可。**
- **三项收尾**(§2):低地址退休代理计数措辞;`TEACHING_VALIDATION` 编译开关分离验证/部署内核(部署内核无 getcpu/pin),部署内核 4 MiB 变体的双核短烟测 **PASS**(§6);磁盘 checker EOF 闭合 + 存在性 + 两个新变异,四份 M3 记录重评通过。

## 2. 先收尾的三项(任务书"先收尾")

| # | 复审点 | 处理 |
|---|---|---|
| 1 | `userRetiredH` 只看 PC<0x8000_0000、不读特权态、含 ROM 提交 | M3 报告 §2/§6/§9-10 与 harness 注释改称**低地址退休代理计数**,不宣称精确 U 态 instret;功能结论依靠 `getcpu` 掩码、并发校验和与受控迁移;未为更名重跑长仿真(Codex 明示)。精确 U 态量留待读取 `dbg_priv`(核已导出,未接到 obs) |
| 2 | `kernel-prod` 无条件含 `pin/getcpu` 与调度器 pin 分支 | 新编译开关 **`TEACHING_VALIDATION`**:`getcpu/pin` 系统调用、`struct proc.pin` 与调度器分支只在验证内核编译;部署内核没有这些机制(`sys/out/xv6-m3-to-m4.patch`,7 文件 25 行)。三种内核:`kernel-valid-4`(验证,4 MiB,= M3 语义)、`kernel-deploy-4`(部署,4 MiB,仿真烟测用)、`kernel-deploy-128`(部署,128 MiB,**板上包**);磁盘 `fs-valid.img`(M3 全部程序)与 `fs-deploy.img`(B0 三应用 + `m3par2`(无 getcpu 的双并发计算)+ `m3fs` + xv6 工具,不含需要验证系统调用的程序)。M3 通过的内核/磁盘(`m3/sw/out`)未覆盖。**内存容量**:板上 `kernel-deploy-128` 取 `TEACHING_SIM_MEM_MIB=128`(PHYSTOP 0x8800_0000,与已验收板上 `kernel-128mib` 同一约定,落在 HP0 上 256 MiB 窗口内);仿真烟测用 4 MiB(kinit/kvminit 遍历页数少 32 倍,Verilator 启动约 12 min 而非数十分钟)——两者同源、只差该常量,部署烟测在 4 MiB 上做,板上容量 128 MiB 未在仿真中重复验证(单核 128 MiB 已在板上验收) |
| 3 | `m3_check.py` 磁盘交替检查 EOF 未闭合、无事件时跳过 | 改为:需要磁盘的 profile 必须有 BDEV 事件、严格交替、EOF 闭合(最后为 DONE、OP 数 == DONE 数);新增"删最后 DONE"、"删全部磁盘事件"变异(自测 17/17,`m3/runs/m3-check-selftest-m4.txt`);M3 四份记录重评全部 PASS 且闭合(`m3/runs/recheck-m4/`),原判定文件保留 |

## 3. 构建输入身份

| 项 | 身份 |
|---|---|
| 板级 RTL | `gen/gen-RD2DualBoardConfig/RD2BoardTop.RD2DualBoardConfig.v`(sha `273463a2…`,`gen.txt` 记录生成);配置 `RD2DualBoardConfig` = `RD2AtomicBoardConfig` + `numCores = 2`:无 TL monitor、无事件/原子/块设备 trace、无总线仪器(审计 §2:0 个 `plusarg_reader`、0 个 printf) |
| 核 RTL | `worktrees/mc-dual-xv6/rtl/cpu/tcpu_*.v` 12 文件 + `tcpu_defs.vh`(与 M1–M3 同一 sha 集,fetch32 + 8 项 TLB + 1 KiB I-cache,无 D-cache) |
| 审计(`build/attempt-1/board-rtl-audit.txt`) | 恰 **2 个 `tcpu_core` 实例**,`HART_ID` 0 与 1 各一,`RESET_PC 0x10040`,`MISA_A 1`,无 `FAULT_*` 传参;V2 端口(`req_amo/req_lrsc/resp_scfail/resv_clear`)各连接 2 次;ROM 由 RTL 提取与 `bootrom.teaching.rv64.img` 前 156 字节一致、与单核构建的 `rom_from_rtl.bin` **同 sha**(f1010b83…) |
| 层次(`hierarchy.txt`) | `Top`(shim)→`RD2BoardTop`→`RD2ZynqTop`→`TeachingCpuV2`→`tcpu_*` 全部可达且唯一定义;无 Rocket 子系统模块 |
| 单核基线输入(复用,未改) | `rocketchip_wrapper.v`(板真顶层:PS、引脚、MMCM、两 AXI 边界、HP0 地址翻译 `{4'd1, addr[27:0]}`)、`base.xdc`、`pynqz1_bd.tcl`(PS 预置 50 MHz 晶振、HP0 0x0 起 0x2000_0000)、`clocking.vh`、`AsyncResetReg.v`、`plusarg_reader.v`;shim 由双核 RTL 重新生成(76 端口与基线 `Top` 逐字段相同) |
| 工具 | Vivado v2025.2.1(lin64)Build 6403652,`vivado-env:2025.2` 容器,part `xc7z020clg400-1`,4 jobs;流程 = 已验收 `build-atomic.sh`(密封 manifest → 校验器 → 生成 project Tcl → `m4-build/run_impl.tcl`),差异只在输入与两个校验器的双 hart 版本;`check-tcl.tcl` 因宿主与镜像已无 `tclsh` 改用 Vivado 自带 Tcl 解释器运行(同一脚本,`TCL_CHECK fails=0`) |
| 全部输入 sha | `build/attempt-1/source-MANIFEST.txt`(21 项)、`input-hashes.txt`、`tooling-hashes.txt` |

## 4. 结果:时序与资源(route 后,`build/attempt-1/reports/`)

**40 MHz 收敛,setup/hold 全部满足**(`run-status.txt`、`post_route_timing_summary.rpt`、`impl-check-attested.txt`)。

| 项 | 双核(本次,attempt-1) | 单核 cache 基线(`ips-cache/…/build-cache`,14554 LUT) | 要求 |
|---|---|---|---|
| setup | **WNS +0.396 ns**,TNS 0.000,0 / 37,958 端点失败 | +0.424 ns,0,0 / 24,530 | WNS ≥ 0,TNS = 0 |
| hold | **WHS +0.035 ns**,THS 0.000,0 失败 | +0.036,0 | WHS ≥ 0,THS = 0 |
| pulse width | WPWS +2.000,TPWS 0,0 / 13,305 | 同 | ≥ 0 |
| "All user specified timing constraints are met" | 是 | 是 | 是 |
| `check_timing` 12 类(no_clock、constant_clock、pulse_width_clock、unconstrained_internal_endpoints、no_input/output_delay、multiple_clock、generated_clocks、loops、partial_in/out_delay、latch_loops) | **全部 0** | 全部 0 | 0 |
| 时钟 | `host_clk_i` 周期 25.000 ns = **40 MHz**(MMCM CLKOUT0);clk_fpga_0 100、gclk 125 同基线;无新增时钟 | 同 | 40 MHz,无新时钟 |
| Inter-clock table | 空(无跨时钟路径) | 空 | 空 |
| DRC | PDCN-1569 ×3、RTSTAT-10 ×1(警告),全部位于 `system_i/axi_interconnect_1`(PS 侧 AXI 协议转换器,基线块设计),与基线**规则/数目/位置相同**;无 critical | 同 | 无 critical |
| 方法学 | LUTAR-1 ×3,与基线相同 | 同 | 已阅 |
| 关键路径 | `rd2serial/addr_reg[5]` → `backend/resvValid_0_reg/D`,数据路径 24.422 ns(逻辑 10.699 / 布线 13.723),**46 级**(CARRY4 ×26) | `rd2serial/addr_reg[4]` → `backend/resvValid_reg/D`,24.364 ns,50 级 | — |
| 冻结判定器 `check-impl-reports.py` | **PASS**(4 项人工声明已给出,见 `impl-check-attested.txt`;未声明版本 `impl-check.txt` 为 PENDING×5,按设计) | — | PASS |

关键路径与单核相同性质:TSI 串口写地址寄存器经后端"外部写覆盖预约"判定(地址区间比较链)到预约有效位——M2a 引入的每 hart 预约使这条链在双核里落到 `resvValid_0`;裕量 0.396 ns 真实但不宽(与基线 0.424 同级),未做任何约束/架构改动。

**资源(route 后,`post_route_utilization.rpt`;综合面积不作最终面积)**

| 资源 | 双核 | 单核 cache 基线 | Δ | 可用 |
|---|---|---|---|---|
| Slice LUTs | **22,631(42.54 %)** | 14,554(27.36 %) | +8,077 | 53,200 |
| LUT as Logic | 21,366 | 13,591 | +7,775 | |
| LUT as Memory(LUTRAM) | 1,265 | 963 | +302 | 17,400 |
| Slice Registers(FF) | **11,181(10.51 %)** | 7,011(6.59 %) | +4,170 | 106,400 |
| Block RAM | 0 | 0 | 0 | 140 |
| DSP | 0 | 0 | 0 | 220 |
| BUFG | 1 | 1 | 0 | 32 |

分层(`post_route_utilization_hier.rpt`,LUT / FF):`target` 21,771 / 10,321;**`harts`(hart 0)7,578 / 3,711**,其中 `core`(TeachingCpuV2+tcpu)7,396 / 3,460(csrfile 1,165、muldiv 1,112、ifill+I-cache 1,078、ptw+tlb 724);**`harts_1` 7,557 / 3,689**(core 7,329 / 3,446);`backend`(共享串行原子后端)1,123 / 269;`sbus` 1,150 / 135(两端口 crossbar);`pbus` 1,503 / 409(含 `atomics` 443);`bh`(TLBroadcast)557 / 225;`mbus` 486 / 730;`rd2serial` 649 / 231;`controller`(块设备)520 / 453;`rd2clint` 66 / 194(两 hart 的 msip/mtimecmp);`plic` 57 / 73;`adapter` 660 / 535;PS 侧 `system_i` 202 / 325。单核基线中 `core` 为 7,399 / 3,460——**每核面积与单核相同**(hart 0 的 core 7,396),第二核的成本 ≈ 一个 core(7.3k LUT)+ 第二桥(228)+ crossbar/总线增量(sbus +1.1k、pbus 中 xbar 部分)+ CLINT/PLIC 第二上下文(几十 LUT);后端本身只 −6 LUT(1,129 → 1,123,每 hart 预约替换单预约后逻辑更规整)。

## 5. 部署包与兼容性(任务书"检查新 bit/bin 与 loader/DT/保留内存/host 磁盘路径")

`deploy/`(`MANIFEST.sha256`,`README.md`):`rocketchip_wrapper_dual.bit`(4,045,696 B,sha `4ecccd05…`)→ **payload `rocketchip_wrapper_dual.bit.bin`(4,045,564 B,sha `43e5b414…`)**——转换器 `E1-clock-scaling/bit2bin.py` 先以已验收单核 payload `20fae71e…` 自检(逐字节复现)再转换;`kernel-dual-128mib`(sha `33021237…`)、`fs-dual-deploy.img`(`d8e50269…`)、`fesvr-teaching-static`(与已验收包同 sha `c050eab3…`);验证内核/磁盘另存供参考,标明不上板。

兼容性核对(离线):板真顶层 `rocketchip_wrapper.v`、块设计 `pynqz1_bd.tcl`(PS 预置 50 MHz 晶振、HP0 0x0/0x2000_0000)、`base.xdc` 与单核构建**同一文件同一 sha**(密封 manifest);shim 76 端口与基线 `Top` 逐字段相同;HP0 翻译 `{4'd1, addr[27:0]}` → Rocket 侧 0x8000_0000 起 256 MiB 上半段,`kernel-dual-128mib` 的 128 MiB 落在其中(与 `kernel-128mib` 同约定);设备树保留内存 `0x1000_0000–0x1FFF_FFFF` 与 `mem-preflight` 门禁不受影响(未改任何 PS/DT 文件);host 二进制、`+blkdev=` 磁盘副本约定、TSI 装载/唤醒(host 只写 msip[0],ROM 唤醒 hart 1;ROM 与单核构建 sha 相同)不变;两 hart 的 CLINT 寄存器在架构偏移(msip[1] 0x0200_0004、mtimecmp[1] 0x0200_4008),PLIC 每 hart 一个 M 态上下文、无设备源(部署内核不触碰)。

未来上板步骤、冷启动要求、串口交还门禁与单核恢复方案见 `deploy/README.md`:用户交还板并停止单核会话 → **冷上电** → ARM 侧 `mem-preflight` → `/dev/xdevcfg` 写入 payload 并核对 `prog_done` 与 payload sha → 生产 runner 以 `m4smoke` 类 profile 启动 `fesvr-teaching-static +blkdev=<fs-dual-deploy 新副本> kernel-dual-128mib`;控制台单读者、卡死只能冷重启;单核恢复须**按 hash 指明两种不同工件**:用户当前板上运行的是 IPS **cache** 配置(bitstream `e546c0dd…` → payload **`79a114ae…`**,tag `ips-v1-icache`,`ips-install.sh cache`),"恢复用户原状"指它;而 `ips-restore.sh` 装的是更早的已验收参考镜像(`2cd8a992…` → payload `20fae71e…`),不是用户最近的 cache 配置——两者不得混称(Codex M4 验收备注,`deploy/README.md` 已更正);均须冷上电。**本任务只有离线准备,不代表已获烧写许可。**

## 6. 部署内核短烟测(双核仿真,`runs/smoke-deploy`)

`kernel-deploy-4` + `fs-deploy.img`,双核 FAST 仿真器(M3 的 `sim-dual`,同一 scala 生成物),profile `m4smoke`(b0compute、m3par2、m3fs),`runs/smoke-deploy`,wall 2175 s:**PASS**(`smoke-deploy.check`)——banner 4.1 s、首提示符 752 s;`b0compute` 校验和 `5ADF55920BF7696`;`m3par2` 两并发子进程校验和 `f6d983767e3c5638` / `01d86a21f972f3fa`(无 getcpu,`harts=0x0` 字段无意义)、父进程归并后 `ok=1`;`m3fs` 两子并发文件读写 `ok=1`;硬件:两 hart 退休 24.07 M / 24.50 M,低地址提交 1.26 M / 3.05 M(hart 1 逐采样增长),调度器区间 0.61 M / 0.25 M,trap 296 / 342;153 次磁盘操作严格交替且 EOF 闭合;无 panic、无重复回显/校验和。**部署内核在双核上启动、并发计算、文件校验均正确;板上容量 128 MiB 变体只差内存常量,未在仿真重复(§2-2)。**

## 7. 复跑入口

```bash
M4=/home/engineer/fpga/experiments/multicore/m4
bash $M4/tests/build-sw.sh                                      # 三种内核 + 两种磁盘 + diff + sha
TOPPROJ=teaching bash $M4/gen/gen.sh RD2BoardTop RD2DualBoardConfig $M4/gen/common-board <out>
python3 $M4/tools/board-build/make-top-shim-atomic.py <dual .v> $M4/build/inputs/teaching_top_shim.v
python3 $M4/tools/board-build/make-build-manifest-m4.py $M4/build/inputs/MANIFEST.txt
./coord claim vivado "..."; JOBS=4 bash $M4/tests/build-board.sh <new attempt dir> --with-vivado; ./coord release vivado
python3 experiments/teaching-cpu/m4-prep/scripts/check-impl-reports.py --timing ... --utilization ... --drc ...
python3 riscv-lab/experiments/E1-clock-scaling/bit2bin.py <.bit> <.bit.bin>          # 先以已验收 payload 自检
bash $M4/tests/run-xv6.sh <m3 sim-dual> $M4/sw/out/kernel-deploy-4 $M4/sw/out/fs-deploy.img m4smoke <out> 2000000000 3600 1800
```

## 8. 过程记录(如实)

| # | 事实 | 处理 |
|---|---|---|
| 1 | `check-tcl.tcl` 需要 `tclsh`;宿主机与两个镜像现在都没有(已验收构建时曾有);Vivado 安装内有 `bin/unwrapped/lnx64.o/tclsh8.6` 但不在 PATH | 用 `vivado -mode batch -nolog -nojournal -source check-tcl.tcl -tclargs` 运行同一脚本(`TCL_CHECK fails=0`),记录于 `build-board.sh` |
| 2 | 审计脚本 §5 只看第一个 `tcpu_core` 实例 | M4 副本要求恰 2 个实例、`HART_ID` 0/1 各一(`tools/board-build/audit-board-rtl-atomic.py`);原脚本未改 |
| 3 | `deploy-4` 与 `deploy-128` 内核只差 `TEACHING_SIM_MEM_MIB`,但反汇编按地址归一后仍差数千行(常量装载序列不同导致代码布局整体移位) | 不以反汇编等价作断言;两者由同一构建脚本、同一源码、仅内存常量不同(`build-sw.sh` 记录标志与 sha) |
| 4 | 烟测与 Vivado 并行运行(仿真为单进程轻负载,Vivado 4 jobs) | 均以 coord job 登记;Vivado 期间持有 `vivado` 租约并在完成后释放 |
| 5 | Vivado 全流程 wall 见 MANIFEST(`impl wall`),远低于 3 h 预算,一次成功,无修正重跑 | — |

## 9. 状态

交付物:`worktrees/mc-dual-xv6` 提交 565d33f(未推送);`experiments/multicore/m4/{REPORT,RESULTS,MANIFEST}.md`、`build/attempt-1`(密封输入、校验器输出、project.tcl、Vivado 日志与全部报告、bitstream、`impl-check*.txt`)、`deploy/`(部署包 + README)、`sw/`(隔离 xv6 副本与 `out/`)、`tests/`、`tools/`、`runs/`。M3 收尾:`experiments/multicore/m3` 的 REPORT 措辞、`tests/m3_check.py`、`runs/recheck-m4/`、`runs/m3-check-selftest-m4.txt`。未做:板/JTAG/串口/烧写/push;四核/流水线/D-cache。OPEN `claude-mc-m4-offline-ready`;通过后由用户协调交还板与断电,进入双核板测与固定工作量收益测量。
