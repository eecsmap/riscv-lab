# M0补证验收

2026-09-14：平台审计交付通过，CPU架构契约仍为候选规格。本次独立只读核对，无构建、仿真或板上运行。

## 独立证据

- BootROM.scala：ROM基址0x10000，hang/resetVector为0x10040；生成Top RTL中Frontend复位PC为40'h10040（前轮已核对）。
- `common/csrc/zynq_driver.cc` 构造函数先将SYSTEM_RESET置1再置0；`riscv-fesvr/fesvr/htif.cc:77` 的start先load_program后reset；`tsi.cc:29` 的reset向0x02000000写1。
- `testchipip/bootrom/bootrom.S`：_hang设置mtvec到_start、启用MSIP/MIE、wfi；MSIP异常进入_start，清MSIP、设置mepc=0x80000000后mret。MPP=M来自M-mode陷入，不是未经证明的复位值。
- 本checkout `tilelink/Bundles.scala` TLBundleD具有error；`Edges.scala:368` Get/Put的lgSize是log2字节数，带mask的Put用于部分写。与新版denied/corrupt区分已修正。
- 本地xv6 start.c、vm.c与TLB.scala支持报告中定时中断转SSIP、软件预设PTE A/D及权限分流的说明；控制台采用HTIF/TSI，M1不安排不存在的UART测试。

## 验收范围和后续门禁

允许以该审计分派M1仿真环境与物理总线桥工作。实际mtime频率、旧仿真环境可用性仍待实测，不阻塞审计收口。

M1实施前冻结地址/数据宽度、字节通道/size/mask、单在途、错误和冷启动边界；M2实施前明确C保留、PMP/委派、TLB、原子支持范围和实现语言。受限RMW不宣称完整总线原子或完整A扩展；运行中热复位不支持。S模式对U页的取指禁止与数据SUM权限分开，已补CONTRACT验收注。

原有Rocket镜像/源码未修改，RW13继续延期。本次不是新CPU或总线桥功能验收。
