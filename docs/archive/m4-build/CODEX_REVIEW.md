# M4-b 独立验收 — 2026-09-16

结论：M4-b离线构建验收通过。教学设计已生成位流，40MHz实现满足本阶段判据；不代表板上启动，不授权硬件操作。

## 本轮独立核验

- 读取attempt-1原始run-status及路由报告：synth_design Complete / write_bitstream Complete，均100%；13098网全部路由，0路由错误。
- 封存源清单12项与产物清单8项逐文件SHA256和长度均一致；独立运行check-source-set.py返回0，无遗漏登记RTL/约束，无旧Rocket Top混入。
- 实际报告checker无声明exit2/PENDING，带本次登记声明exit0/PASS；读取DRC具体路径并与基线比对PDCN-1569/RTSTAT-10规则，问题均位于既有auto_pc IP。methodology为该IP内LUTAR-1。保留这些警告，不称零警告设计。
- setup WNS +2.826ns / TNS0，hold WHS +0.031ns / THS0；host_clk_i=40MHz；check_timing无问题；原始CDC报告称All paths are Safely Timed。
- LUT9149(17.20%)，FF3849(3.62%)，Slice2823(21.23%)，BRAM0，DSP0。无超限。
- 读取综合及route网表审计：无未解析黑盒，教学层次存在，plusarg/tail/fault/dbg名称匹配均0。名称扫描本身不是功能等价证明，结合M4-a结构性关闭证据认可本阶段结论。
- 独立解析教学与回退.bit的a/b/c/d/e字段：配置数据从偏移132开始、长度4045564；两份.bin均等于对应完整配置数据按32bit字节反转后追加字节00000020。初始仅尝试截尾、以及假定追加零/FF填充的探针断言失败；改为解析实际格式后两份对应关系均确认，未发现镜像损坏。未重跑Bootgen或实际加载。

## 边界及下一步

本轮仅重放离线checker及文件核验，未重新运行Vivado、未打开checkpoint重新查询网表、未重新仿真CPU；实现证据来自Claude交付的真实工具报告/日志。本轮没有板/JTAG/串口/SD访问。

下一步M4-c需用户另行授权：按已准备runbook核验回退与PS侧工具，先最小marker，再DDR、CLINT、非法地址裸机测试。所有板测结果尚未知，不能以时序通过代替功能通过。mtime400kHz与DTB1MHz差异、M/C及xv6支持依旧未解决。
