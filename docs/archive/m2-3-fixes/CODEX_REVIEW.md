# M2-3补证复核，2026-09-15

结论：暂不通过，正常RTL尚未发现新故障；验证链仍有三个具体缺口。

## 实际运行

使用归档模拟器，未重新编译。独立六项en矩阵、三项watch正向退出0，watch-dup退出21。两个归档checker均退出0。run-a/gate源码、ELF及模拟器/C++共140项哈希校验通过。原始日志、退出码与完整commit轨迹保存在 `codex-review-IJQCkN/`。

六个已使能注入确实分别发生在341/343/346/348/350/351周期，认可这部分改进，不再要求重做屏蔽语义测试。

## 1. DUP_STORE只篡改观测计数，没有重复写事件

`src/tb/tcpu_harness.v:273`后的do_write只执行一次存储赋值；DUP_STORE唯一作用是令watch_writes加2而不是1（第280行）。故退出21只证明“计数错误可被检查出来”，不证明“重复存储副作用可被独立检查出来”。报告所称模型实际重复施加写不成立。

需真实第二次write-apply事件，计数器在每个实际事件上无条件+1，不直接读取故障开关。可在模型内部排队重放一次相同写、保持单个总线响应，用统一apply路径记录cycle/地址/数据/序号。只重复一个选定写即可；同周期对同一RAM位置重复非阻塞赋值不能代表两个独立副作用事件。

## 2. watch矩阵实际注入load，不是store

独立watch-clean/resp/slow全部fire PC=0x800001e4，反汇编为watched_load；watched_store=0x800001ec。报告表格所称store请求/响应期不成立。armed后第一个数据访问是load，注入器未限定write或目标PC。

需限定命名store的PC及写访问；响应期用锁存的事务信息，不看不再有效的req字段。checker核对实际fire PC、write、地址和等待状态。原六项load矩阵保留。

## 3. retired是整场累计，不能证明IRQ前退休，ARCH还检查错目标

driver结尾用pc_count[fire_pc]打印FIRE TARGET；en-wbland的fire_pc已是after_target=0x8000022c，所以其retired=1统计的是中断返回后执行的下一条，不是target_insn=0x80000228。checker忽略target记录的PC并仅检查retired>=1；其他行也未验证先退休再IRQ。

需使用ELF符号指定固定target_insn，保存其请求握手/响应完成/退休cycle及首次IRQ cycle，在IRQ发生时采样退休次数（应为1），并检查真实RF/CSR更新已落地。不要靠结束时总数推断顺序。watch_resp虽然已输出但未门禁；watched_store的50次退休也未门禁。补自动精确计数及有序事件链，并加错目标/错顺序记录的checker反例。

下一步OPEN `codex-m2-3-event-evidence-fixes`。旧src/run-a/gate原样保留；未接SoC/上板。
