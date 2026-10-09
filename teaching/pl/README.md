# teaching/pl — 纯 PL：核 + BRAM 内存，不经过桥、TileLink 和主机

核只认 PHYSICAL_PORT。协议那头接什么它不知道，所以容量允许时可以直接接一块 BRAM，不要 PS、不要 fesvr。
这里是那块 BRAM 和一个能上板的顶层。

| 文件 | 内容 |
| --- | --- |
| `tcpu_bram_mem.v` | 可综合的协议内存：64 位宽、字节使能、`$readmemh` 初始化；ready 寄存一拍，响应在接受后一拍；越界和原子请求回 `resp_error` |
| `tcpu_pl_top.v` | 核 + 内存 + tohost 嗅探。输出 `tohost_valid`、`tohost_code`、`tohost_pass`、`commit_valid`，直接接 LED 或 ILA |
| `tb_pl.v` | 仿真这个顶层：时钟、复位、看 tohost。没有 harness，没有监视器 |

## 运行

```sh
make pl-sim                              # 你的核，默认跑 step1/s1_tohost.S
make pl-sim CORE=../rtl/cpu              # 参考核
make pl-sim PL_TEST=path/to/other.S      # 换程序；它必须自己定义 tohost
VCD=1 make pl-sim                        # 波形到 out/pl/sim.vcd
```

`make stepN` 检查的是契约，`make pl-sim` 检查的是集成：同一个程序，同一个核，换一个内存。两者都该 PASS。
参考核 92 拍，第 1 步的 4 字节取指核 51 拍。

## 内存必须守的规则

写 `tcpu_bram_mem.v` 时守住的几条，换别的存储实现时同样要守，harness 的监视器在 `make stepN` 里查它们：

- `req_ready` 是寄存器，看到 valid 的下一拍才拉高，永不组合直通；
- 响应在接受的下一拍，绝不在握手那一拍；一次只有一个请求在飞；
- 读返回整个 8 字节对齐的字，核自己按地址选通道；写只改 `wmask` 为 1 的字节；`req_size` 两边都不需要；
- 地址不在 `[MEM_BASE, MEM_BASE + MEM_BYTES)` 内回 `resp_error = 1`，不碰内存，不能静默回 0；
- `req_amo` 或 `req_lrsc` 非零时回 `resp_error = 1`：第 8 步之前这块内存不做原子操作，也不把它们当普通访问做。

## 容量

| 板 | PL BRAM 总量 | 这块内存合理上限 | 能跑什么 |
| --- | --- | --- | --- |
| PYNQ-Z1 (xc7z020) | 140 × 36 Kb ≈ 630 KB | 256 到 512 KiB | 第 1 到 8 步的全部测试和探针；xv6 不行，它要 128 MiB，在 PS 侧 DDR 上 |

`MEM_BYTES` 要是 2 的幂。64 KiB 是 16 个 RAMB36。

## 上板要点（Vivado）

- `INIT_HEX` 给绝对路径或放进工程源文件；Vivado 综合支持 `initial` 块里的 `$readmemh`，仿真和综合用同一份 hex。
- 写口用字节循环、读口进寄存器，这是 Vivado 推断带输出寄存器的 BRAM 的写法。综合报告里确认它没有退化成分布式 RAM。
- 时钟用板上 125 MHz 过 MMCM 分到 40 MHz 左右，和基线一致；复位接一个按钮，`tohost_pass` 和 `commit_valid` 接两个 LED。
- `TOHOST_ADDR` 参数要和链接结果一致：`riscv64-unknown-elf-nm prog.elf | grep tohost`，s1 的是 `0x8000_0080`。
- 这个顶层没有 CLINT 和 MMIO，第 4、5 步的中断测试和 SoC 测试不在它上面跑。
