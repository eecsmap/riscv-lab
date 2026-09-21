# CPU-SV39 补修后验收 — 2026-09-18

裁决：非叶保留位缺陷修复认可，Sv39串行无TLB仿真阶段验收通过。范围不含A/PMP、xv6启动、新版综合或板测。

## 本轮独立执行

- HASHES.txt 3579/3579核验通过（/tmp/codex-sv39-fixed-hashes.log）。活动PTW相对old-rtl仅增加非叶U/A/D判错条件，保持G/RSW及叶权限路径。
- 原独立nonleaf.cpp从当前RTL新构建：合法控制成功；U/A/D各置位均第1次PTE读取后fault=1、cause=13、reads=1，四例PASS。证据codex-review/nonleaf-fixed.log，旧失败日志保留。
- 注册codex-sv39-review，从源码重编完整核门禁至codex-review/core-fixed，CPU_SV39_DONE fails=0：sv01–06及sv09三时序，提交记录一致；异常退休检查、PTW在途中断、遍历中复位、三具名故障与控制、33次SU回归均通过。
- 同一新sv09在旧PTW退出11，旧PTW普通sv02退出0，复现具名缺陷而非泛化超时。
- 新构建模拟器24点复位扫描至codex-review/reset-fixed，RESET_SWEEP_DONE fails=0，含陈旧PTE响应排空。
- 复用交付soc-run2二进制独立重跑boot11：实际退出0，M3-SV39-OK，启动链/1中断/2同步异常与AXI检查通过；5084请求均恰一次回应，读785、写2166闭合。日志codex-review/boot11-replay.log及.exit。

## 证据边界

完整IM/C/M2-3及全部SoC回归本轮核查Claude新归档通过记录，未独立再次全跑；SoC未独立重新构建。首次boot11独立运行漏保存旁置.exit，checker正确拒绝；第二次实际重跑并保存退出码后通过，没有补造首次退出码。两份日志都保留。

sv09的软件显式检查load epc及三类别cause/tval、18次trap和存储不变；不能把报告中的“所有epc均逐项断言”当作本用例事实。核心共用精确trap路径及既有跨页/权限测试支持本阶段有限验收，后续新增原子异常须保留精确epc门禁。

下一任务codex-cpu-atomic-platform-contract：审计真实仲裁/外部竞争边界及xv6最小适配，不默认核内普通RMW为完整A。主线仍是最简多周期单口教学CPU替换Rocket运行xv6。
