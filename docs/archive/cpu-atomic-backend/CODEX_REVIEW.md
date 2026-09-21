# CPU-A 后端首次独立验收 — 2026-09-19

裁决：单元功能局部认可，阶段暂不通过。以下具体问题补修后再收口，不进入CPU-A实现。

## 独立执行范围

- 607/607交付哈希通过（/tmp/codex-atomic-hashes.log）。审阅REPORT/DESIGN、AtomicBackend/RD2BridgeV2/PhysPortV2及测试驱动、runner/scorer；核对旧TLBroadcast的clientFn。
- 使用run5交付二进制重跑14场景：10正向进程0/score0，readerr/no-kill/sc-early负向进程0/score1，wrong-source断言退出-6/score1。没有独立重新生成Scala或重编模拟器。
- 可复跑脚本codex-review/review.py；每场景原始日志、真实退出码与score均在codex-review/，没有修改交付档。

## R1 阻断：验证链未覆盖CPU响应与事务闭合

独立对amo-basic重跑日志做三种变异，均仍score=0、fails=0：

1. 删除全部D_OUT；
2. CPU_RESP的每个data改为0xdeadbeefdeadbeef；
3. 删除全部CPU_RESP。

证据missing-d、wrong-cpu-data、missing-cpu-response的.log/.score。score.py未处理CPU_REQ/CPU_RESP；pending会被覆盖且结束不检查残留，没有完整逐source请求/应答配对。V2Driver只在resp.fire推进索引，不检查data/error/scFail。因此REPORT声称CPU stand-in检查响应和每A恰一D超出了实际证据。

还需修runner：neg只要sim非0或score非0就认可，除124外没有强制指定断言/检查原因，崩溃或无FINISHED也能冒充缺陷被检出。修成每个负例精确错误签名，基础设施错误不算成功。

## R2 阻断：拟定插点丢失CPU客户端身份，DRAM区域判断不足

DESIGN把AtomicBackend放在TLBroadcast/MemoryBus后；本地rocket-chip/tilelink/Broadcast.scala clientFn将所有clients折叠成单一name="TLBroadcast"。AtomicBackend按name="teaching-phys"查找并require存在。按文档拟定链直接接入会触发该require；当前三master直连TLXbar单测绕过了这个变换。这是源码确定的不匹配，尚未动态elaborate拟定SoC，不能宣称已接入。

需明确保留身份的真实插点或通过变换的事务身份方案，补最小真实拓扑生成/测试。可仍用事务驱动器，CPU指令实现不在此次补修范围。不能把整个TLBroadcast source范围都当CPU，也不能硬编码未证明的ID。

RD2BridgeV2把supportsArithmetic && supportsLogical当作DRAM白名单；既有pbus也有原子自动机，能力不等于DRAM区域，不能保证裁定的MMIO原子禁止。补显式声明支持的地址区域/属性并检查合法元数据（包括保留lrsc=3拒绝）。

## R3 阻断：缺少返回背压、写阶段错误及可靠排空检查

V2Driver和外部master的resp/D ready恒1，现有场景未测返回背压与scResult跨D缓冲绑定。需要V2响应停顿、D通道buffer/stall、两侧独立延迟，验证数据/error/scFail保持、正常/失败SC不污染后继。

errors区域同时读错和写错；原子遇读错已停止，不能据此覆盖AMO读成功后Put报错。新增明确write-only故障及一次错误终结、不重复写检查。drain评分当前只要求存在DRAIN_DONE/HOLD_RELEASE标记，应以实际Get/Put/D事件约束先后和hold期间无新代请求；不能仅靠标记存在证明排空完成。

## 文档修正与边界

严格串行节点在LR的D未完成时不接收其他新事务，因此“外部写在LR读pending时被backend接受并失效”的措辞不成立：外部源可在此时提出请求，在LR完成后、SC前获准，再使预约失效。这是合法简化，测试应区别offered/accepted，不能为满足措辞破坏串行设计。DESIGN及PhysPortV2旧注释还写mark在TL A握手推入，活动实现是在CPU req握手推入，需同步。

实际SoC后端插入、source映射及R-BOOT全链尚未完成；旧SoC四M3与旧V1回归不能代替新路径集成证据。此次不要求CPU指令/xv6/板测，保留默认Rocket。
