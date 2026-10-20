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
# 1. 固件：板上的 DELAY
riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -O2 -ffreestanding -fno-pie -nostdlib -nostartfiles -static \
    -Wl,--no-relax -T ../../software/probes/link.ld -o blink.elf start.S blink.c
python3 ../tools/elf2hex.py riscv64-unknown-elf-objcopy riscv64-unknown-elf-nm blink.elf blink.hex blink.tohost
# 2. bitstream（约十分钟）
vivado -mode batch -source build.tcl -tclargs ../work/cpu $PWD/blink.hex $PWD/build
# 3. 装进 PL：JTAG 用 hw_server 和 program_hw_devices，或者按本仓库原来的方式转成 .bit.bin 由 PS 侧装载
```

通电或按 BTN3 复位后，LED0 以 1 秒周期闪，按 BTN0、BTN1、BTN2 分别点亮 LED1、LED2、LED3。

板上的东西这边没有跑过：`mcu_board.v` 用了 Xilinx 原语，iverilog 不认；引脚按 PYNQ-Z1 的 master XDC 写，用前对一下
你那块板的版本。时序上这个设计的关键路径在核里，40 MHz 应该有大量余量，`build/timing.rpt` 会给出 WNS。

## 换程序

现在改一行 C 要重新综合。两条改进路线，都没做：`updatemem` 配 MMI 文件直接改写 bitstream 里的 BRAM 内容，几秒钟；
或者在 RAM 里固化一个串口 bootloader，上电等串口送镜像。有了串口（MCU-1）之后做第二条。

## 下一步 MCU-1

串口。借 picosoc 的 `simpleuart.v` 换成这里的从设备接口，固件加 `putchar`、`getchar` 和一个精简 printf，testbench
加 TX 位流解码。那时核最好已经到第 3 步，访问错地址会 trap 而不是静默。
