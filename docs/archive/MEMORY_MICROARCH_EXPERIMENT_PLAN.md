# CPU 内存接口与微架构实验方案

2026-09-17 用户要求重新聚焦并分派：以TEACHING_CPU_XV6_PLAN.md顶部新路线为准。近期修复块设备真实重启故障，随后推进M/C、特权/MMU及xv6；完整通用复位故障矩阵/PL热重配置及性能正交实验移出关键路径，未完成项保留为待办，不算验收通过。

2026-09-14 优先级调整（用户已批准）：近期主目标改为最简自研多周期CPU接入现有Rocket/PYNQ-Z1/xv6体系并替换Rocket。当前执行以 [教学CPU接入计划](experiments/TEACHING_CPU_XV6_PLAN.md) 为准；先M0替换契约审计，再M1总线通路/M2执行核/M3 xv6。RW13及后续性能矩阵延期，RW10–RW12成果保留。新教学核首版允许单套req/resp物理内存口；下文I/D分离等安排仍是原实验设计，不约束新主线首版。ISA/特权/MMU与板级版本待本地M0证据确认。

本文记录目标设计、决策理由和实验边界；实际完成情况以 [执行记录](experiments/EXECUTION.md) 为准。2026-09-11 整理：第 3～5 节为统一接口设计依据，不代表当前 Sodor 已实现。

## 1. 实验目的

本实验研究以下因素对 CPU 正确性、性能、资源和可移植性的影响：

1. 统一内存端口与指令/数据分离端口；
2. 异步分布式 RAM、同步 BRAM、PS AXI DDR 和 MIG DDR；
3. 当拍/固定一拍/多拍/可变延迟响应；
4. 单 outstanding request 与流水化、多 outstanding request；
5. 不同流水线级数和不同 I/D 仲裁策略；
6. 是否加入 Cache，以及 Cache 对外部内存延迟的隐藏效果。

实验的核心要求是：每次尽量只改变一个因素，其他 CPU、软件、地址空间和测试条件保持不变。

## 2. 现有工程基础

当前工程已经具备一个可用的 Rocket + PYNQ-Z1 + XV6 系统，可作为系统级参考实现和最终真实硬件验证平台。

前期微架构实验使用 Chipyard 中的 Sodor。Sodor 已提供 1/2/3/5-stage 以及 microcoded 实现，3-stage 支持 Harvard/Princeton 选择，并且有异步和同步 scratchpad 相关实现。Sodor 适合裸机 benchmark 和流水线实验，但不应被强行扩展成完整 Linux CPU：它主要是 RV32I、M-mode 教学核，不支持虚拟内存。

因此采用双平台策略：

```text
Sodor + Chipyard/Verilator：微架构、协议、延迟和端口实验
Rocket + PYNQ-Z1/XV6：Cache、AXI、DDR、虚拟内存和系统级验证
```

## 3. 总体架构

### 3.1 固定 CPU 边界，切换后端组织

目标 CPU 边界固定为 I（取指，只读）和 D（数据，读写）两个逻辑端口，各自具备完整的 req/rsp ready/valid 通道。“统一协议”是两路使用相同协议，不是强制 CPU 只暴露一路端口。

- `UNIFIED`：仲裁 I/D 请求，共享一个后端服务端口；响应按记录的来源返回。
- `SPLIT`：I/D 使用两个后端服务端口，可并行服务；不必是两块物理 RAM，也不意味着分离地址空间。

两种模式保持 CPU 接口、程序和地址映射不变。复制存储、分银行或双口 RAM 必须另记容量、冲突和一致性语义，不能把资源翻倍隐藏成单纯的端口切换。下图表示共享后端的示意；SPLIT 不经过同一个单端口仲裁瓶颈。

```text
                         ┌── I request client
CPU core ────────────────┤
                         └── D request client
                                  │
                                  ▼
                         Memory System
                 ┌─────────────────────────┐
                 │ I/D arbiter             │
                 │ latency adapter         │
                 │ outstanding queue       │
                 │ optional cache          │
                 └─────────────────────────┘
                                  │
                          generic memory bus
                                  │
                 ┌─────────────────────────┐
                 │ distributed RAM         │
                 │ BRAM                    │
                 │ PS AXI DDR              │
                 │ MIG DDR                 │
                 └─────────────────────────┘
```

CPU 不直接依赖 LUTRAM、BRAM、AXI 或 MIG。所有后端差异都通过 adapter 隔离。

### 3.2 为什么不让 CPU 只暴露一个端口

I/D 分离把取指和数据访问的竞争放在明确的实验边界，便于保持 CPU 不变而替换仲裁策略或后端端口数，也为流水取指和未来 I/D Cache 留出空间。代价是额外的握手线路、响应来源状态和仲裁逻辑。

CPU 单端口仍可实现流水线，并不等于只能做顺序多周期核；但它会在 CPU 内提前合并 I/D，后端难以恢复两路并行度，不适合作为本实验的固定边界。非流水 CPU 同样可以使用分离端口，只是不必同时发起两路请求。

## 4. 统一内存协议

### 4.1 请求通道

```text
req_valid
req_ready
req_addr       // 字节地址
req_write
req_wdata
req_wstrb      // 每字节写使能
req_size       // 访问大小；固定字宽实验可约定为常量
// 基线 CPU 端口不要求 source 或 id 字段
// 共享仲裁层记录 I/D 来源；乱序扩展才按需增加事务 id
```

### 4.2 响应通道

```text
rsp_valid
rsp_ready
rsp_rdata
rsp_err
// rsp_id 仅在显式采用事务 id 的协议扩展中出现
```

### 4.3 协议规则

```text
req_fire = req_valid && req_ready
rsp_fire = rsp_valid && rsp_ready
```

1. `req_valid=1` 且 `req_ready=0` 时，所有请求字段必须保持不变；
2. 请求方不能通过撤销 `valid` 来取消未握手请求；普通 flush 不豁免保持规则，reset 的协议边界见 4.6；
3. 在无 reset 打断且双方最终继续服务的条件下，每个被接受的请求对应且仅对应一个响应；写请求也返回响应，写响应中的 `rdata` 可以忽略；
4. 对同一请求，其 rsp_valid 不得在接收请求的边沿已经有效。请求在边沿 k 接收，响应 valid 最早在 k 之后的周期内由寄存状态驱动，响应最早在边沿 k+1 接收；不能仅拉低 rsp_ready 来掩盖过早的 rsp_valid。允许旧请求 A 的响应与新请求 B 的请求在同一边沿握手；
5. `rsp_valid=1` 且 `rsp_ready=0` 时，valid 不得撤销，所有响应字段保持不变，直到握手边沿（含该边沿）；请求保持规则同样包含最终握手边沿；
6. 允许响应延迟任意多拍；
7. 单 outstanding 基线按每个 CPU 逻辑端口计数，从 `req_fire` 到对应 `rsp_fire`（不是仅到 rsp_valid）占用一个名额。共享后端的在途上限另行配置；基线共享后端也为 1，不应混淆“每端口 1”和“整个系统 1”；
8. 同址读写、未对齐访问、错误响应和字节写语义必须明确记录。

响应“至少下一拍”是统一接口的下限，不是固定延迟保证。分布式 RAM 可以被 wrapper 延迟一拍，AXI/MIG 则可以自然地延迟多拍。

### 4.4 写地址、写数据与后端桥接

写地址、写数据、字节使能和访问大小属于同一个请求 payload，由一次 `req_fire` 一起接收，不拆成独立的写地址/写数据通道。读请求使用相同请求通道，写字段在读请求中不参与操作，但等待握手期间仍保持稳定。

桥接器接收时保存完整请求：AXI 写事务再拆成 AW 和 W，分别保持 valid/payload 直到各自握手，记录两路完成状态，不假定 AW/W 同拍或固定先后顺序；B 响应转换为 CPU 写响应，R 响应转换为 CPU 读响应。桥接器必须预留所需状态/缓冲，不能让 CPU 通过重复提交请求补发 W。CPU 响应被背压时，缓存响应或对后端施加合法背压。

写响应表示该接口定义的写完成/错误结果，不仅表示请求已入队。直连 RAM 在写入生效后返回；直接 AXI 桥在收到 B 后返回。这不自动保证持久化、其他代理的缓存一致性或跨 I/D 顺序；加入写回 Cache 后必须单独定义完成点、fence 和可见性。

### 4.5 决策与权衡

| 决策 | 选择理由 | 代价与替代方案 |
|---|---|---|
| CPU I/D 分离，后端可共享 | 端口竞争可独立配置；便于取指与访存重叠 | 多一组通道及来源状态；CPU 单端口只作为单独微架构变体 |
| 每端口 req/rsp 两套 ready/valid | 请求接受与完成分离；支持可变延迟和双向背压 | 需要缓冲/状态；start/done 对严格单事务 FSM 更直观，但必须另定 busy、接受及结果保持规则，流水扩展也需额外协议 |
| 写地址、数据合为一个 req | CPU 不必处理 AW/W 配对及独立完成状态；适配简单 RAM 直接 | 不能分别提前发送地址和数据；AXI 拆分及缓存成本留给桥接器 |
| 同一请求至少下一拍响应 | CPU 不依赖组合内存路径，便于替换同步存储和外部内存 | 牺牲组合读的当周期使用机会，增加寄存器/等待；零拍另设协议变体 |
| 写也有响应 | 统一完成、错误和在途名额释放机制 | 增加响应流量，可能限制写吞吐；posted write/写缓冲需另定排序与错误报告规则 |
| 从单 outstanding、有序响应开始 | 少量状态即可建立可验证基线 | 多拍内存下难以隐藏延迟；后续分别增加队列和并发请求能力 |
| 有序多 outstanding 不强制公开 ID | 顺序队列即可配对响应 | 仲裁层仍需来源队列；乱序完成需 ID 或内部重排；AXI ID 不必暴露给 CPU |

“下一拍响应”不等于“只能隔拍传输”：延迟为 1、无背压并支持同边沿释放/复用名额时，可以每拍接收一个请求。是否支持这种周转是单独实现参数；保守 FSM 可以插入空拍，但不能归因于协议本身。增加 outstanding 也只有在 CPU 能产生独立请求且后端有服务能力时才可能提高吞吐。

异步 LUTRAM 直接组合输出并非一概违例，关键是响应下限和停顿期间稳定性。默认 wrapper 保存响应数据/有效位；仅锁存地址，在其他端口可能写同址时不足以保证稳定。无保护的组合输出可能让接收方在最终握手时读到另一请求或被更新后的数据；直接将当前 req 映射成 rsp 还会违反最小延迟约束。BRAM/DDR 也必须保证背压时不丢响应，不能只依赖存储类型。

### 4.6 顺序、取消与待冻结细节

- 无 ID 模式按每个 CPU 端口的请求接受顺序返回。共享后端按实际握手记录来源并路由；某一路背压可能阻塞后续响应，这是需测量的队头阻塞。
- 分支 flush 不得直接撤销挂起的 valid 或丢掉已接受请求的响应。取指需要记录过期请求并接收后丢弃结果；推测 store 不得在获准执行前产生外部副作用。
- reset 是显式协议边界：须定义清空哪些队列、如何处理后端仍可能返回的旧响应；局部 CPU reset 不等于取消已进入 AXI/DDR 的操作。
- I/D 分离不自动保证 store 后取指、MMIO、fence 或自修改代码的顺序。接入这些程序前须确定排序策略；首轮微基准避免依赖未定义行为。
- 字宽、字节序、窄写数据的字节位置与 wstrb 对应、跨字/未对齐访问、错误编码、同址双口冲突和仲裁公平性，须在 RTL 接入前冻结并测试，不视为已实现能力。

### 4.7 目标接口与当前实现的边界

2026-09-14 RW12补充：固定HoldIDMMIOIrq核、单端口scratchpad仲裁后的共享延迟S={0,2,8}已验收。共享链协议/竞争/背压/响应归属、慢取指redirect、性能矩阵及身份/统计补修已验证；S同时影响响应时延与服务间隔，不能归因为纯物理RAM延迟。边界统计仅为全程序量，ROI事务数与等待拍数未测；核心/端口组织/真实FPGA后端对比尚未完成。证据与独立复验见EXECUTION最新RW12记录。

2026-09-14 进度更新：三级单端口 HoldIDMMIOIrq 保持型配置、MMIO 捕获与限定中断交错覆盖已验收；RW11 固定该核心的 D 口接受等待 A={0,2,8} × 响应延迟参数 R={0,2,8} 矩阵及 A=0/R={1,3,4} 补点已验收。R 是现有适配器参数（非端到端内存延迟），I 路径未注入，队列/多在途与实际 BRAM/DDR 尚未覆盖。计数、原始日志、身份哈希和负向门禁的独立复核入口见 `experiments/EXECUTION.md` 的 RW11 记录。下面保留初始实现状态，不作为当前完成清单。

截至 2026-09-11：

- 目标是上述 I/D 分离、双 ready/valid、合并写请求协议，尚未接入 Sodor RTL。
- 当前三级 Sodor 使用原生 `MemPortIo`：req 为 Decoupled，resp 为 Valid，没有 rsp_ready；单/双端口配置还涉及原生仲裁和缓冲差异，不能当作已完成的正交端口实验。
- 六项冒烟通过的是锁定版本加 scratchpad adapter 兼容补丁，不是完整目标协议验证。该适配器的 HellaCache s1_kill 也不是给通用 req/rsp 增加取消权。
- Python reference memory 只实现单端口、单 outstanding 协议子集；它未接入 Sodor，也不是双端口或随机背压 RTL 验证。
- 下一步先核验 ROI/cycles/instret，再逐步接入新协议。记录、补丁与验收证据见 `experiments/EXECUTION.md`。

## 5. 可配置实验变量

推荐通过配置文件、Verilog parameter 或 Chipyard Config Fragment 控制：

```text
CORE_PIPELINE       = SODOR_1 / SODOR_2 / SODOR_3 / SODOR_5
PORT_MODE           = UNIFIED / SPLIT       // 后端端口组织，CPU I/D 边界不变
MEM_BACKEND         = BEHAVIORAL / DIST_RAM / BRAM / PS_AXI / MIG
PROTOCOL_MODE       = REGISTERED / COMB_EXPERIMENT
RESPONSE_LATENCY    = 1 / 2 / 4 / 8 / RANDOM // REGISTERED 模式至少 1
SERVICE_INTERVAL    = 1 / 2 / 4             // 后端接受请求的最小间隔
MAX_OUTSTANDING_I   = 1 / 2 / 4 / 8
MAX_OUTSTANDING_D   = 1 / 2 / 4 / 8
BACKEND_OUTSTANDING = 1 / 2 / 4 / 8         // 每个后端服务端口的上限
TURNOVER            = CONSERVATIVE / SAME_EDGE_REPLACE
ARBITRATION         = I_PRIORITY / D_PRIORITY / ROUND_ROBIN
CACHE               = OFF / I_ONLY / D_ONLY / I_D / UNIFIED
```

实验中禁止后端隐式改变协议。例如异步分布式 RAM 即使可以更早产生数据，也必须经过 latency adapter 才能参与“统一一拍响应”实验。

以上是目标配置轴，不是现有脚本已支持的选项；只测试经过实现和验证的组合。随机延迟按序模式需防止后发请求越过先发请求，并记录种子。测量分别记录响应首次可用延迟、等待 rsp_ready 的时间和请求服务间隔。

## 6. 实验阶段

### 阶段 A：协议和内存模型

目标：不依赖具体 FPGA 后端，先证明协议正确。

后端模型：

```text
zero/comb model       // 仅用于研究同拍响应
1-cycle model
2-cycle model
固定 8-cycle model
随机 1~30-cycle model
```

测试内容：

- 请求方在 `ready=0` 时保持 valid 和 payload；
- 响应方在 `ready=0` 时保持 valid 和 payload；
- 连续读写、读写混合、背压和 reset；
- 每个请求都收到且只收到一个响应；
- 响应不会早于规定周期；
- 同址读写行为符合定义。

产物：协议 assertion、波形、随机测试结果和 reference memory model。

### 阶段 B：Sodor 流水线实验

先在 Chipyard/Verilator 中运行 Sodor：

```text
B1：各流水实现先使用各自原生 scratchpad，确认功能基线
B2：3-stage 原生单/双端口冒烟（已完成，含兼容补丁）
B3：3-stage 接入目标协议，验证停顿、响应与 flush
B4：同一个改造后核心切换后端端口组织和延迟
B5：按需适配其他流水实现，记录额外控制逻辑差异
```

只有完成可变延迟适配和正确性验收的核心，才逐个改变内存延迟：

```text
0/comb、1、2、4、8、随机延迟
```

该阶段使用裸机 benchmark，不使用 XV6/Linux，避免虚拟内存和系统软件差异干扰微架构比较。

不能把原生单周期核直接配成“一拍内存”而认为只改变了存储：它依赖组合读，适配后可能改变执行周期结构。不同级数的比较先作为整体实现比较，不自动归因为流水级数。0/comb 属于单独协议变体。

### 阶段 C：统一端口与 I/D 分离端口

保持流水线和内存延迟不变，只改变端口组织：

```text
C1：统一单端口，I/D 竞争
C2：统一单端口，I priority
C3：统一单端口，D priority
C4：统一单端口，round-robin
C5：I/D 双端口
C6：双口 BRAM
```

观察：

- I/D 竞争 stall；
- 取指被数据访问阻塞的周期；
- 数据访问被取指阻塞的周期；
- 指令吞吐率和 CPI；
- 双端口 RAM 的资源代价。

### 阶段 D：流水化和 outstanding request

```text
D1：单 outstanding，保守周转，响应完成后的下一周期才发新请求
D2：单 outstanding，固定一拍响应，同边沿释放/复用名额，可每拍接受一个请求
D3：多个 outstanding，保证按序响应
D4：多个 outstanding，允许乱序响应，加入 ID/tag
```

该阶段专门区分三个概念：

```text
单笔延迟
请求吞吐率
可同时在途的请求数量
```

不能只用平均内存延迟解释性能变化。

### 阶段 E：真实 FPGA 内存后端

目标协议接入后，在同一个 CPU 内替换后端；换用 Rocket 属于独立系统级参考，不声称仅改变存储器：

```text
E1：分布式 RAM
E2：BRAM
E3：通用协议到 PS AXI 的桥接；或借用 Rocket 作为独立 DDR 参考
E4：MIG + PL DDR 板卡
```

PYNQ-Z1 的板载 DDR3 属于 PS 侧内存，Rocket/PL 访问时通过 PS AXI 路径；不能把它当作 PL 内部 BRAM 直接使用。MIG 实验则用于外部 DDR 连接到 PL 的其他板卡。

### 阶段 F：XV6/Linux 系统验证

使用现有 Rocket + PYNQ-Z1 + XV6 工程作为 reference：

```text
F1：现有 Rocket + DDR + XV6 基线
F2：不同 AXI 访问延迟模型
F3：不同 Cache 配置
F4：不同 DDR/AXI 吞吐和 outstanding 配置
F5：XV6 usertests
F6：Linux 启动和基本用户态测试（若目标平台完成）
```

Sodor 不作为 Linux/XV6 的最终平台；如果需要，可让 Sodor 访问 AXI/DDR 做裸机验证，但不把完整虚拟内存和 Linux 支持加入 Sodor。

## 7. 性能和资源指标

### CPU 性能

```text
cycle counter
instret counter
CPI / IPC
I-fetch stall cycles
D-access stall cycles
I/D arbitration stall cycles
memory wait cycles
branch flush cycles
```

### 内存系统

```text
请求数量
响应数量
平均/最大响应延迟
请求吞吐率
响应被背压的周期数
平均 outstanding 数量
I/D 请求比例
```

### FPGA 实现

```text
LUT
FF
LUTRAM
BRAM
DSP
最大工作频率
关键路径
功耗（可选）
```

必须同时报告两种性能：

1. 相同目标频率下的 CPI；
2. 各设计达到自身最大频率时的实际执行时间。

测量使用相同 ELF、相同 ROI（被测程序区间），排除程序加载与初始化。先用已知动态指令数校准 instret，计算 CSR 读数边界开销，并验证停顿不重复计数；当前三级 Sodor 的 retire 停顿问题仍待实测修复。没有统一计数口径之前不发布 CPI。各类 stall 可重叠，未经互斥定义不能直接相加。

## 8. 基准程序

### 微架构阶段

- RISC-V ISA tests；
- Fibonacci、矩阵访问、memcpy；
- 顺序读写；
- 随机读写；
- 指令密集型程序；
- Load/Store 密集型程序；
- I/D 竞争专用 benchmark；
- 分支密集型程序。

### 系统阶段

- XV6 boot；
- shell；
- `usertests`；
- 文件系统压力测试；
- 自定义内存带宽和延迟测试；
- Linux boot 和用户态 smoke test。

同一组裸机 benchmark 应尽量同时运行在 Sodor 和 Rocket 上，但两者的绝对 CPI 不直接比较，只比较在各自基线上的相对变化。

## 9. 正确性验收标准

每个配置至少满足：

1. ISA tests 通过；
2. 协议 assertions 无失败；
3. 请求和响应计数完全匹配；
4. 随机延迟和随机背压测试通过；
5. 内存数据与 reference memory model 一致；退休指令序列/架构状态与 ISA 参考或已知测试期望一致（内存模型本身不提供退休序列）；
6. Rocket 基线继续通过 XV6 boot 和 usertests；
7. FPGA 综合无关键时序违例；
8. 记录资源利用率、Fmax 和测试版本。

## 10. 推荐目录结构

```text
experiments/
  protocol/
  memory-models/
  sodor/
  rocket/
  benchmarks/
  scripts/
  results/
  configs/
docs/
  MEMORY_MICROARCH_EXPERIMENT_PLAN.md
```

每个结果目录包含：

```text
config.json
build.log
simulation.log
performance.csv
resource-utilization.rpt
timing.rpt
README.md
```

## 11. GitHub 仓库策略

现阶段不建议立即新建独立 GitHub repo。当前已经有 Rocket/PYNQ-Z1/XV6 工程，应先在同一个工程或其实际 Git 仓库中加入：

```text
docs/MEMORY_MICROARCH_EXPERIMENT_PLAN.md
experiments/
```

这样可以保留已有的 bitstream、rootfs、启动脚本和硬件验证记录。

等出现以下情况之一时，再拆出独立仓库：

- Sodor 实验代码已经可以独立构建；
- 需要公开实验结果和复现实验环境；
- 需要与 Chipyard upstream 分离管理；
- 需要多人协作或独立 issue/CI；
- 实验代码与 Rocket/XV6 产品工程的发布周期不同。

独立仓库届时可只保存实验框架、配置、脚本和结果索引，Rocket/XV6 工程通过 submodule 或外部路径引用。

## 12. 第一阶段的具体任务清单

1. 把本方案加入项目文档；
2. 定义统一 req/rsp Bundle 或 SystemVerilog interface；
3. 实现一个带随机延迟和随机背压的 reference memory；
4. 添加协议 assertions；
5. 选择 Sodor 3-stage 作为第一个实验核；
6. 完成 Princeton/Harvard 和 unified/split 的最小配置；
7. 添加 cycle、instret、I/D stall、memory latency 计数器；
8. 跑通阶段 B、C 的基线矩阵；
9. 再接入分布式 RAM和BRAM；
10. 最后使用现有 Rocket/XV6 工程验证 PS AXI DDR。

第一阶段的完成标志是：同一个 benchmark 可以在至少四种配置下运行，协议 assertions 全部通过，并生成可比较的 CPI、stall 和资源结果。

## 13. 参考资料

- [UCB riscv-sodor 官方仓库](https://github.com/ucb-bar/riscv-sodor)
- [Chipyard 官方文档](https://chipyard.readthedocs.io/en/latest/)
- [Chipyard Memory Hierarchy](https://github.com/ucb-bar/chipyard/blob/main/docs/Customization/Memory-Hierarchy.rst)
- [AMD/Xilinx 7-Series Distributed RAM](https://docs.amd.com/r/en-US/ug474_7Series_CLB/Distributed-RAM-Data-Flow)
- [AMD/Xilinx 7-Series Block RAM](https://docs.amd.com/r/2025.1-English/ug953-vivado-7series-libraries/BRAM_SDP_MACRO)

## 14. 冻结的 Chipyard/Sodor 版本

前期实验固定使用：

```text
Chipyard：1.14.0
Chipyard release commit：0acc1e1de2d3284bcd4d876956932a013ffe1949
Sodor：910a2e83ce206e86372927ec3e0b8056953f7d95（该 release 锁定）
默认工具链：Chisel 6.7.0 / Scala 2.13.16；USE_CHISEL7 必须未设置
```

选择理由：

1. 使用正式 release 的完整提交和配套 submodule 锁定实验输入；
2. 1.14.0 默认使用 Chisel 6，Chisel 7 是显式开启的可选路径；
3. 官方初始化脚本提供 `--sodor`，支持按需初始化；
4. 先尝试原版构建和裸机测试；如需兼容补丁，保留原版失败证据及最小补丁，通过后再开始目标接口改造。

2026-09-10：此决策替代先前的 1.12.3 建议。正式 release 尚不代表本机验证通过，实际进度见 `experiments/EXECUTION.md`。

初始化时必须使用新目录和锁定的 submodule：

```bash
git clone --branch 1.14.0 --depth 1 https://github.com/ucb-bar/chipyard.git chipyard-experiment
cd chipyard-experiment
unset USE_CHISEL7
./scripts/init-submodules-no-riscv-tools.sh --sodor
```

不得把现有 2018 年的 `fpga-zynq/rocket-chip` submodule 替换成这套实验环境的依赖。
