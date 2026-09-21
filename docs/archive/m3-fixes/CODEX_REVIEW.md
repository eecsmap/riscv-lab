# M3补修复核（2026-09-16）

暂不最终通过。认可严格CPU事件状态机及四漏检修复；退出专项仍选错事务。

独立证据：codex-review-Aevj6g。归档二进制跑marker同配置mode0/1/2，限制10000周期，分别退出0/2/2。15项日志变异探针全部拒绝，72条源码/ELF/模拟器输入哈希通过。未重新编译或上板。一次probe --help误调用的参数异常日志保留，按正确位置参数重跑的probes.log为准。

## 阻断：tohost地址不是退出事务的充分条件

TeachingCpuSoc.scala armed只匹配write和tohost地址。htif_putc同样写该地址：独立及归档withheld命中PC=0x80000040，数据0x0101000000000054（字符T），真正exit_store为0x80000084、成功退出数据1。errored的cause7也发生在0x80000040。程序没有执行到退出，因此“没有HOSTDONE”不能证明host已看到退出时仍不会提前结束。

必须按exit_store PC、tohost地址、写属性及HTIF退出payload限定，锁存到该响应。新增有界长延迟正向，让真实HOSTDONE出现于退出响应/退休之前，随后正常完成；缺响应/错误反例不能判PASS。检查明确的实际命中事件和退出事务序号，控制台写不应被拦截。这里不接受用换一个不打印字符的程序来掩盖匹配器错误。

## 仍须兑现的AXI验证范围

当前AXI检查只有总数ar==rlast、aw==wlast==b以及beats>=bursts，未记录/核对ID或ARLEN/AWLEN；不能声称已做逐burst闭合。按上轮任务补长度、LAST位置、ID、RESP及未完成事务门禁，或者先交实际拓扑和限制证据申请缩小范围，不能以总数相等替代已经要求的验证。增加错误beat数/LAST/ID的定向日志负例。

下一步OPEN codex-m3-tail-target-fixes；旧证据保持，M3尚不收口。
