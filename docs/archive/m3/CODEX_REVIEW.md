# M3首次验收，2026-09-16

结论：认可教学CPU接旧SoC的功能进展，暂不最终验收，退回验证链窄修。

证据 `codex-review-ptWiWx/`。独立使用归档模拟器运行四程序×两时序：8项退出0；原ROM退出0但illegal checker确认异常启动路径。源码/ELF/生成RTL与模拟器输入清单69项哈希通过。未重新生成或编译RTL，未上板。

首次尝试传-s12345被fesvr拒绝（255），属于复跑参数错误，不是CPU失败；原始日志保留，去掉该参数的retry日志为采纳证据。后续runner应明确seed传递方式并记录，不能C++解析了就假定fesvr也接受。

## 阻断1：事件门禁不能证明一一对应或完整启动链

独立checker-probes.py对原正常日志作只读流式变换，以下四项均错误返回0：重复一条RESP、增加没有REQ的RESP、删除AXI统计、删除MRET提交记录。脚本和输出保留在证据目录。

根因：req/resps用字典覆盖重复序号，只检查请求集合减响应集合，没有检查反向集合/唯一性/单在途；启动检查未核对mret，wait次数未限定在IRQ之前；AXI统计完全未门禁。check-m3.py也不自行核对进程退出码、Assertion与host成功。

要求事件状态机严格核对请求/响应唯一、顺序、单在途、未知响应及字段；完整ROM等待→MSIP→中断→mret→精确DRAM入口。AXI闭合按burst/LAST/ID和未完成事务记录验证，读写均非零。每项必须有合成错误日志被拒的反例。

## 阻断2：缺退出store负例和可靠尾部完成定义

TeachingCpuDropRespConfig丢的是首次ROM取指响应（seq0/0x10040），不是退出store。它证明启动访问能超时，未证明host已观察到tohost后CPU退出响应/退休缺失不会提前判成功。

busy只等于req.fire到resp.fire的outstanding位，未覆盖尚未握手的req.valid，也未覆盖响应后等待退休。C++遇hostdone且!busy便结束，需由可靠事件门禁确认退出响应与退休；当前仅boot01显式传exit符号，其他程序没有尾部验证。

要求用命名exit_store/tohost精确注入响应长延迟/错误或丢弃，在host候选成功后仍不能提前通过；保留正常对照。明确未握手承诺、响应、退休与桥空闲的关系，用事件判定而非固定多跑。每个程序都核验其实际符号。不得用首次取指丢响应替代此覆盖。

## 阻断3：全矩阵自动门禁与可复现交付不完整

run-m3.sh只自动检查6/8正向日志，遗漏delay CLINT和badaddr；除marker程序外不检查各程序标记/尾部。CLINT/错误路径/AXI专项证据主要留在文字报告，需转为门禁，异常原因/epc/tval按程序精确核对，不能额外同步异常被handler跳过后仍算正常通过。

run-m3.sh本身未快照到m3c-run，也未纳入src.sha256。补完整runner/checker/配置/种子与执行退出码归档；不要求因为验证链缺口重构CPU或升级ISA。

下一步见OPEN codex-m3-validation-fixes。旧产物保留；未批准上板。
