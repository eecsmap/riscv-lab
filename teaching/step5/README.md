# 第 5 步：进入系统

目标：你的核不再接测试台的内存模型，而是装进一个真正的片上系统（RD2 SoC）：TileLink 总线、启动 ROM、CLINT、
DDR 控制器、一个由主机程序驱动的串行链路。主机把程序装进 DRAM、叫醒你的核、通过 HTIF 控制台收它打印的字。
做完这一步，你的核第一次在"系统"里打印出一行字。

这一步**不写新的 RTL**。前四步做的东西已经够了：这一步检验它们在真实总线和真实启动链上是不是都对，
并学会读一个系统级的运行记录。

## 这一步在哪

| | |
| --- | --- |
| 前面 | 第 1 到 4 步：RV64I、访存、异常和 M 模式 CSR、中断。全在纯 Verilog 测试台里，内存是一个数组 |
| 这一步 | 同一个核，换成真的 SoC：地址由总线译码，没人认领的地址会回 error，中断线来自真的 CLINT，程序由主机装载 |
| 后面 | 第 6 步 S/U 模式，第 7 步虚拟内存，第 9 步在这个 SoC 上跑 xv6 |

**这一步不涉及**（遇到了可以先不管）：

- SoC 本身怎么写：它是 Chisel（Scala）生成的 Verilog，`soc/scala/teaching/` 有源码，这里当作给定的零件。
- 中断控制器 PLIC（`0x0C00_0000`）和块设备（`0x1001_5000`）：地址图里有，第 9 步 xv6 才用。
- 上板：这个 SoC 的板上版本需要 PS 侧的主机程序，留到第 9 步。现在的上板练习用 MCU-0（第 4 步的应用）。
- 多核、原子指令、压缩指令。

## 开始之前

```sh
make step4            # 必须全过：启动链要用到中断（msip 叫醒）和 load access fault（boot04）
make step5            # 先用约 20 秒把 SoC 和你的核一起 verilate，再跑 boot01 到 boot04
```

需要两个不在本仓库里的工具：Verilator 5 和 fesvr（主机侧的 HTIF 服务）。脚本默认用这台机器上的那份；
换机器时用 `VERILATOR_ENV=`、`FZ=`、`FESVR=` 指过去（见 `tools/step5-build-sim.sh` 的开头）。
你的核的任何 `.v` 改了，下次 `make step5` 会自动重新 verilate。

## 做什么

| TODO | 内容 |
| --- | --- |
| 1 | `make step5`，四个启动程序全过 |
| 2 | 从 boot01 的日志里找出启动链的每一环，填 `TODO.md` 里的表 |
| 3 | 写你自己的第一个系统程序：复制 `step5/hello.c` 到 `work/hello.c`，改成你的话，`make step5-run PROG=work/hello.c` |
| 4 | 追踪 boot04：一个没人认领的地址，怎样从总线一路变成你的核里的 load access fault |

细节在 `TODO.md`。

## 系统里有什么

```
            ┌──────────── RD2 SoC（生成的 Verilog，step5/sim/RD2Harness.RD2BootConfig.v.xz）────────────┐
 你的核 ── 桥（核的 req/resp 端口 → TileLink）── TileLink 总线 ──┬── boot ROM      0x0001_0000
                                                               ├── CLINT         0x0200_0000
                                                               ├── PLIC          0x0C00_0000
                                                               ├── 块设备        0x1001_5000
                                                               ├── 错误设备      0x0000_3000
                                                               └── TLToAXI4 ── DRAM 0x8000_0000（256 MiB）
                                                    串行适配器 ── 主机（fesvr，C++，在仿真进程里）
            └────────────────────────────────────────────────────────────────────────────────────────┘
```

CLINT 的偏移和 MCU-0、第 4 步的 harness 一样：`msip` +0，`mtimecmp` +0x4000，`mtime` +0xBFF8。
所以第 4 步的中断知识在这里原样适用。地址图里没有的地址（比如 `0x5000_0000`），总线回 error。

## 启动链

SoC 把你的核的 `RESET_PC` 参数设成 `0x10040`。启动 ROM 只有 156 字节：

```
10040: auipc a0,0 ; addi a0,a0,-64     a0 = 0x10000
10048: csrw  mtvec, a0                 trap 入口 = ROM 开头
1004c: li    a0, 8 ; csrw mie, a0      只开 MSIE（软件中断）
10054: nop                             （原来是 csrw mideleg，教学核没有，改成 nop）
10058: csrs  mstatus, a0               MIE = 1
1005c: wfi ; j 1005c                   等主机叫醒

10000: ...                            hart 0 先给其他核写 msip（这里只有一个核，读回 0 就停）
10074: sw    zero, 0(a1)               清掉自己的 msip，中断线落下
10078: a0 = 0x8000_0000 ; csrw mepc
10094: csrc  mstatus, 0x80             MPIE = 0：程序开始时中断是关的
10098: mret                            跳到 0x8000_0000，你的程序
```

主机那边同时在做：

1. 通过串行适配器把 ELF 写进 DRAM（日志里一串 `EVA AW addr=0x8000…` 写事务）；
2. 写 CLINT 的 `msip` = 1（日志里 `IRQLEVEL msip=1`）；
3. 然后一直轮询程序的 `tohost`。

核这边：`wfi` 循环里的某次 S_IF_REQ 看到 `mip.MSIP & mie.MSIE & mstatus.MIE`，进中断（`TRAP interrupt=1 cause=…03
epc=0x1005c`），ROM 处理程序清 msip、设 mepc、`mret`，下一次取指就是 `0x8000_0000`。

这条链上用到的每样东西你都已经做过：`RESET_PC`（第 1 步）、CSR 和 `mret`（第 3 步）、`mie` 和 S_IF_REQ 采样（第 4 步）。

## 控制台怎么工作（HTIF）

程序里有一个 64 位的变量 `tohost`（`tests/cpu/m3tests/htif.S`，段 `.htif`）。主机从 ELF 的符号表找到它的地址，
通过串行链路反复读它：

| `tohost` 的值 | 意思 |
| --- | --- |
| 0 | 没有命令 |
| `1<<56 \| 1<<48 \| c` | 控制台：打印字符 c |
| `(code<<1) \| 1` | 程序结束，退出码 code |

主机取走一个命令后把 `tohost` 写回 0；程序写下一个命令前要等它变回 0。所以控制台很慢：`hello.c` 打一行
23 个字花了约 6100 拍，每个字约 260 拍，基本都在等主机隔着串行链路来读。C 程序用 `step5/console.h`
（`con_puts`、`con_puthex`、`con_putdec`），汇编程序用 `htif.S` 的 `htif_putc`、`htif_puts`、`htif_exit`。

## 测试

| 程序 | 测什么 | 期望 |
| --- | --- | --- |
| boot01_marker | 整条启动链，加最简单的控制台 | 打印 `TEACHING-CPU-M3-OK`，1 次中断（启动用的 msip），0 次同步异常 |
| boot02_clint | 真 CLINT：`mtime` 在走，`mtimecmp` 触发定时器中断，`msip` 触发软件中断 | `M3-CLINT-OK`，3 次中断 |
| boot03_ddr | 经 TileLink 到 AXI4 到 DRAM 的各种宽度、对齐的读写 | `M3-DDR-OK` |
| boot04_badaddr | 读 `0x5000_0000`（没人认领）：总线 error → load access fault，cause 5，epc 是那条 load，tval 是那个地址 | `M3-BADADDR-OK`，1 次同步异常 |

每个程序有两套独立的证据：程序自己的检查（失败就以非零码退出），以及仿真日志的检查（`step5/check/check-m3.py`、
`check-axi.py`）。日志检查逐条核对：每个请求恰好一个响应、启动链按顺序发生、中断和异常的次数和现场、退出的那条
store 真的退休了、AXI 事务配平、SoC 里的 TileLink 协议监视器一次都没报错。

你的核的参考数据（2026-11-04）：boot01 6520 拍，boot02 74832 拍，boot03 21966 拍，boot04 7029 拍。
参考核：8523、125523、31987、9389 拍。

## 失败了先看哪里

失败时除了 FAIL 行，还会打印一段"核做了什么"：第一次取指在哪、主机什么时候拉的 msip、进了几次中断、
有没有走到 0x8000_0000、最后停在哪。前三行是把你的核的对应部分拿掉、实际跑出来的现象；后两行是推断，没有实测。

| 现象 | 多半是 | 去看 |
| --- | --- | --- |
| boot01 `no host result`；`first fetch: 0x10040`，`interrupts taken: 0 <-- ... still waiting in the ROM's wfi loop` | 中断没被接受：`irq_pending` 恒为 0、`mie`/`mstatus.MIE` 写不进去，或者判定不在 S_IF_REQ | 第 4 步 TODO 1、2、4 |
| boot01 `no host result`；`first fetch: 0x80000000 <-- should be 0x10040`，一串 illegal instruction | 核没用 `RESET_PC` 参数，自己写死了起始地址。程序还没装进去就开始执行 0x8000_0000 的垃圾 | 复位里的 `pc <=` |
| boot04 `tohost = 1`，`synchronous traps: 0`，`failure code 1` | 访存的 `resp_error` 没变成 access fault：坏地址的 load 静默地拿了 0 | 第 3 步 TODO 4（总线错误） |
| `Assertion failed` 加 TileLink 监视器的信息 | 核违反了总线握手（比如 `req_valid` 拉高后没等 `req_ready` 就撤掉） | 第 1 步的端口契约；先跑 `make step1-all` |
| 编译期 `%Error` | Verilator 比 iverilog 严格：多驱动、先用后声明、宽度不配 | `out/step5/sim-*/verilator.log` |

日志都在 `out/step5/`：`<程序>.log` 是完整事件记录，`.console` 是程序打印的字，`.check` 是日志检查的逐项结论。

## 为什么可以相信这些测试

- 四个启动程序和两个检查脚本是这个项目当初验收"教学核接入 SoC"（M3）时用的原件，只是搬了过来（来源和哈希在
  `provenance.json`）。检查脚本的上一版放过了四份篡改过的日志（重复响应、孤立响应、删掉 AXI 统计、删掉 `mret`
  退休），现在这一版就是为此重写的，文件开头的说明记录了这件事。
- 参考核和你的核都 4/4 通过。
- 失败表的前三行是实测：拿掉中断、写死起始地址、忽略总线错误，三个坏掉的核分别在预期的程序上、以预期的方式失败。
- 这一步没有变异开关：要验证的是集成，坏法就是上面这几种。

## 自测问题

<details><summary>1. 为什么复位向量是 0x10040，不是 ROM 开头的 0x10000？</summary>

0x10000 是 trap 入口（ROM 把 `mtvec` 设成它）。复位后先跑 0x10040 那段"设 mtvec、开中断、wfi 等待"，
被 msip 叫醒后才进 0x10000 的处理程序。两段代码共用一个 ROM，入口不同。
</details>

<details><summary>2. 主机往 DRAM 里装程序的时候，你的核在干什么？会不会读到装了一半的程序？</summary>

在 ROM 的 `wfi` 循环里转圈（`wfi` 在你的核里是空操作，所以是忙等，一直在取 ROM 里的指令）。它不会去取 0x8000_0000，
因为跳过去只有一条路：msip 中断加 `mret`，而主机是装完才写 msip 的。顺序由主机保证，不靠时间。
</details>

<details><summary>3. 如果你的核的 `wfi` 在 MIE = 0 时也会被 msip 叫醒并进中断，启动还会成功吗？</summary>

这里 ROM 先把 MIE 置 1 再 `wfi`，所以看不出区别。规范说：`wfi` 被 `mip & mie` 唤醒与 MIE 无关，但**进不进 trap**
由 MIE 决定。一个"MIE = 0 也进 trap"的核在这里能过，在别的程序里会出错。测试只能证明测到的情况。
</details>

<details><summary>4. boot04 里，error 是谁产生的？经过了哪几层才变成 cause 5？</summary>

地址 0x5000_0000 不在任何设备的范围里，由 TileLink 总线这一层给出错误应答，不是哪个真设备；
桥把它变成你的核端口上的 `resp_error = 1`（日志 `RESP ... error=1`）；你的核在 S_MEM_WAIT
看到它，进 S_TRAP，cause 5、tval = 地址、epc = 那条 load（日志 `TRAP interrupt=0 cause=…05`）。
</details>

<details><summary>5. `hello.c` 为什么不能直接写 `x / 10`？</summary>

RV64I 没有除法指令（M 扩展，第 11 步），编译器会生成对 `__udivdi3` 的调用，而 `-nostdlib` 没有这个函数，链接失败。
`console.h` 的 `con_putdec` 用减法凑十进制。xv6 在第 9 步面对的是同一个问题。
</details>

<details><summary>6. 控制台每个字要约 260 拍。如果程序不等 `tohost` 变回 0 就写下一个字，会怎样？</summary>

前一个字还没被主机取走就被覆盖，丢字。`tohost` 是一个单元素的邮箱，"非零 = 满"就是它的握手信号。
</details>

## 做完能玩什么

- **你的第一个系统程序**（TODO 3）：打印一行字，加上它花的周期数和指令数。
- **测 CPI**：在 `hello.c` 里循环跑一段代码，用 `mcycle`、`minstret` 算每条指令多少拍。对比 boot 日志里一次 DRAM 读要多少拍。
- **系统里的定时器中断**：把第 4 步的 `irq_blink` 搬过来，处理程序里打印一个点代替翻转 LED。CLINT 地址一样，
  启动代码要自己设 `mtvec`（ROM 设的那个指向 ROM）。
- **崩溃报告**：写一个 trap 处理程序，遇到同步异常就打印 `mcause`、`mepc`、`mtval` 再退出，然后故意访问 `0x5000_0000`。

**还做不到**（后面的步骤解决）：

- 运行不可信的程序：所有代码都在 M 模式，能改任何 CSR、访问任何地址。第 6 步 U 模式。
- 每个程序有自己的地址空间：第 7 步虚拟内存。
- 跑一个真的操作系统：第 9 步 xv6，在这同一个 SoC 上。
