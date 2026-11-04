# MCU-0：核 + 路由器 + RAM + CLINT + GPIO，灯在板上闪

第一个能在物理世界看到结果的里程碑。核用你第 2 步的（RV64I，不需要 CSR、trap 或中断），固件是 C 写的轮询程序：
LED0 按 CLINT 的 `mtime` 定时翻转，LED1 到 LED3 实时映射 BTN0 到 BTN2，BTN3 是复位。

## 结构

```
tcpu_core ── PHYSICAL_PORT ── mcu_router ──┬── mcu_ram    0x8000_0000  BRAM，64 KiB，hex 初始化
                                           ├── mcu_clint  0x0200_0000  msip +0，mtimecmp +0x4000，mtime +0xBFF8
                                           └── mcu_gpio   0x1001_0000  OUT +0（LED），IN +8（{sw, btn}）
mcu_board：125 MHz → MMCM ×8/25 → 40 MHz，BTN3 复位，mcu_top 在里面
```

路由器守 PHYSICAL_PORT 契约：ready 寄存一拍，接受后一拍选中从设备，再一拍回响应；没映射的地址和原子请求回
`resp_error`。从设备接口是固定一拍延迟的 `sel / we / addr / wdata / wmask → rdata`，加一个外设就是再写一个这样的
模块加一行地址比较。地址图和 harness 一致，所以第 4 步的中断测试里软件看到的 CLINT 就是这一个。

## 仿真

```sh
make mcu0-sim                    # 你的核；期望 RESULT PASS
make mcu0-sim CORE=../rtl/cpu    # 参考核
VCD=1 make mcu0-sim              # 波形在 out/mcu0/sim.vcd
```

testbench 扮演板子：装载固件，看 LED，在第二次翻转后按下 BTN0 和 BTN2，第四次翻转后松开。PASS 要求 LED0 翻转
至少 6 次且每个间隔在 DELAY 到 1.25×DELAY 拍之间、按钮映射被看到又被清除、全程没有总线错误。仿真里 DELAY 是 4000
拍（`MCU0_DELAY`），板上固件默认 20,000,000，40 MHz 下半周期 0.5 秒。参考核的仿真结果：间隔 4180 拍，映射延迟 135 拍。

固件 `blink.c` 编译选项 `-march=rv64i`，Makefile 会用 objdump 确认里面没有乘除和 CSR 指令，所以它一定能在
第 2 步的核上跑。

## 上板

```sh
cd teaching
make mcu0-fw                     # 板上的固件：build/blink.hex，DELAY=20,000,000（MCU0_BOARD_DELAY 可改）
make mcu0-bit                    # Vivado 批处理构建，约十分钟；产物 mcu0/build/mcu_board.bit，日志 build/vivado.log
make mcu0-prog                   # JTAG 烧写（hw_server + program_hw_devices），只动 PL，PS 不受影响；BIT=... 换别的 bitstream
```

`make mcu0-bit` 等价于 `vivado -mode batch -source build.tcl -tclargs <core-dir> <blink.hex> <out-dir>`，三个参数都要，
参数不全脚本会直接退出。

通电或按 BTN3 复位后，LED0 以 1 秒周期闪，按 BTN0、BTN1、BTN2 分别点亮 LED1、LED2、LED3。

### 参考核的第一次构建（2026-10-21，Vivado 2025.2.1，xc7z020clg400-1）

| 项 | 值 |
| --- | --- |
| 综合 + 实现 + bitstream | 约 3 分钟 |
| WNS / WHS（25 ns 周期） | +9.414 ns / +0.049 ns，关键路径约 15.6 ns，40 MHz 余量很大 |
| LUT 总计 | 6597，其中核 6002（寄存器堆 3112），路由器 480，CLINT 97 |
| FF | 2704 |
| BRAM | 16 个 RAMB36（64 KiB RAM），DSP 0 |

`mcu_board.v` 的原语 iverilog 不认，所以板级顶层只在 Vivado 里验证；引脚按 PYNQ-Z1 的 master XDC 写，用前对一下
你那块板的版本。

**2026-10-21 第一次上板：** 学生核（第 2 步，4 态加访存态）的 bitstream 经 JTAG 烧入，综合实现 165 秒，
WNS +9.328 ns，LUT 2740（核 2436，寄存器堆 2210），FF 792，BRAM 16。烧写走 `program.tcl`，PS 侧 Linux 不受影响。
注意烧入 MCU-0 后 PL 上不再有 AXI 从设备，PS 不能再访问 0x43C0_0000 那段地址。

## 第 4 步：中断版闪灯（`APP=irq_blink`）

同样的硬件，换一份固件：LED0 由定时器中断翻转，主循环只映射按钮，完全不看时间。需要做完第 4 步的核。

```sh
make mcu0-sim APP=irq_blink              # 期望 RESULT PASS，SUMMARY 里 irqs=6 sync_traps=0
make mcu0-bit APP=irq_blink              # 产物 mcu0/build-irq_blink/mcu_board.bit
make mcu0-prog BIT=mcu0/build-irq_blink/mcu_board.bit
```

| 文件 | 作用 |
| --- | --- |
| `trap_start.S` | 启动代码：栈、清 bss、`mtvec` 指向 `trap_entry`。`trap_entry` 保存调用者保存的 16 个寄存器，调用 C 的 `trap_handler(mcause, mepc)`，恢复，`mret` |
| `irq_blink.c` | 处理程序：`mtimecmp += DELAY`，翻转 LED0。主循环：关中断，读改写 GPIO_OUT 的 LED1..3，开中断 |

三个要点：

- **`mtimecmp += DELAY`，不是 `mtime + DELAY`。** 截止时刻落在固定网格上，处理程序晚到几拍也不会累积漂移。
  所以单个间隔可以比 DELAY 略短（上一次晚、这一次准），testbench 对中断版的判定是 DELAY ± 1/8，而不是轮询版的
  "不短于 DELAY"。
- **推后 `mtimecmp` 同时也是"清中断"。** `mtip` 是电平 `mtime >= mtimecmp`，不推后，`mret` 之后马上又进来。
- **共享的 GPIO_OUT 要在关中断时读改写。** 处理程序拥有 LED0，主循环拥有 LED1..3，两者写同一个寄存器。主循环读出之后、
  写回之前如果来了中断，写回会把旧的 LED0 盖回去，丢掉一次闪烁。这是第一个"临界区"。

testbench 在 `APP=irq_blink` 时加了 `+need_irq=1`：从核的 trap 端口数中断次数，要求每次翻转至少一次中断、
没有同步异常。轮询版固件在这个判定下会失败，所以 PASS 说明 LED 确实是中断驱动的。

仿真结果（DELAY=4000）：学生核间隔 4006 到 4029、一次 3933，按钮映射延迟约 350 拍；参考核 3963 到 4093。
映射比轮询版（135 拍）慢：testbench 恰好在 LED0 翻转的那一拍按下按钮，这时处理程序正在跑，主循环要等它 `mret` 回来；
主循环每圈也多了一次 GPIO 读和两条 CSR 指令。

## 第 4 步：两个任务的抢占式调度（`APP=tasks`）

最小的"操作系统内核"：两个任务都是死循环，谁也不让出 CPU，靠定时器中断轮流运行。

- 任务 A：忙等 `mtime` 来定时，翻转 LED0。
- 任务 B：不停地把 BTN0..2 映射到 LED1..3。

没有中断的话，任务 A 会永远卡在忙等里，按钮永远到不了 LED。所以 testbench 看到按钮映射，就证明发生了抢占。

```sh
make mcu0-sim APP=tasks                  # DELAY 默认 40000（见下），期望 RESULT PASS
make mcu0-bit APP=tasks                  # mcu0/build-tasks/mcu_board.bit
```

| 文件 | 作用 |
| --- | --- |
| `task_start.S` | `trap_entry` 把**全部** 31 个寄存器和 `mepc` 存进当前任务栈上的 256 字节帧，调用 `trap_handler(frame, mcause)`，切到它返回的帧，恢复，`mret` |
| `tasks.c` | 处理程序：`mtimecmp += SLICE`，记下当前任务的帧，换成另一个任务的帧返回。`main` 给任务 B 伪造一个"刚被打断在第一条指令前"的帧，然后自己变成任务 A |

和中断闪灯相比多出来的东西：

- **要存全部寄存器。** `trap_start.S` 只存调用者保存的那一半就够了，因为处理程序总会回到同一段代码，s 寄存器由 C 的调用约定保住。
  调度器会回到**另一个**任务，那个任务的 s 寄存器必须是它自己的。
- **"切换任务"就是"换一个栈指针"。** 每个任务的状态都躺在它自己的栈上，处理程序只是返回另一个帧的地址。
- **新任务靠伪造的帧启动。** 帧里 `mepc = task_b`、寄存器全 0；第一次切过去时，`mret` 就"返回"到了 task_b 的第一条指令。
- **临界区。** 两个任务都写 GPIO_OUT，`gpio_set` 关中断做读改写，理由和中断闪灯一样，只是这次打断你的是另一个任务。

时间片是 DELAY/16，板上约 31 ms。一次上下文切换要存取 64 个字，在这个多周期核上要几百拍，所以仿真把 DELAY 提到
40000（时间片 2500 拍），不然切换开销会吃掉大部分时间片。仿真结果（学生核）：LED0 间隔 40003 拍，按钮映射延迟约
2400 拍，正好约一个时间片，因为任务 B 要等轮到它；96 次中断，没有同步异常。参考核：间隔 39983 到 40033 拍，映射延迟约 2360 拍。

固件用 `-mcmodel=medany` 编译：程序在 0x8000_0000，默认的 medlow 模型用 `lui` 寻址静态变量，够不到那里。

## 换程序

现在改一行 C 要重新综合。两条改进路线，都没做：`updatemem` 配 MMI 文件直接改写 bitstream 里的 BRAM 内容，几秒钟；
或者在 RAM 里固化一个串口 bootloader，上电等串口送镜像。有了串口（MCU-1）之后做第二条。

## 下一步 MCU-1

串口。借 picosoc 的 `simpleuart.v` 换成这里的从设备接口，固件加 `putchar`、`getchar` 和一个精简 printf，testbench
加 TX 位流解码。那时核最好已经到第 3 步，访问错地址会 trap 而不是静默。
