# CPU-SU D-1…D-10：Codex 最终裁定

2026-09-18。本文优先于本目录原SPEC/DECISIONS建议；Claude先同步文档与测试，再按codex-cpu-su-implementation实施，无需再次等待规划审批。仅授权Bare阶段S/U，不授权Sv39、原子、软件启动链改动或上板。

| 项 | 裁定 | 冻结内容及理由 |
|---|---|---|
| D-1 | 采用，修正理由 | medeleg可写掩码0xB3FF。这是本实现选择，不是规范要求所有这些位必须可委派；M中异常仍不得下委派。保留不支持原因位为0。不能声称原timervec reflect全部变成死代码：M中异常等仍可能走M路径，本轮不删它。 |
| D-2 | 采用 | satp只支持Bare，所有读回0；不支持MODE的整次写无效，Bare非零域归零。明确本阶段不能启动依赖Sv39的xv6，不能以忽略写入伪称支持分页。 |
| D-3 | 采用 | MPP合法0/1/3，写2归0；mret归最低支持特权U，并按规范更新MIE/MPIE及MPRV。 |
| D-4 | 本阶段采用 | TVM/TSR固定0，明确是本实现WARL取值，不提供相关拦截能力；S的satp/SFENCE.VMA/SRET允许，U的权限检查仍须真实实现。 |
| D-5 | 采用并补测试 | TW固定0，WFI在M/S/U均立即完成、正常退休一次的NOP。不是低功耗睡眠，也不能免测：加本核三模式定向测试，不要求QEMU与该允许选择一致。 |
| D-6 | 有条件采用最简路线 | 本阶段零PMP条目，PMP CSR非法，保留普通物理范围/总线错误检查。未来xv6教学配置可最小条件化移除两条PMP初始化，必须独立补丁、保留Rocket配置；**现在不改start.c**。不宣称S可被隔离于M的内存，也不承诺运行依赖PMP的软件。 |
| D-7 | **不采纳默认实现** | 不以CPU内两笔普通读写加“不取中断”作为正式A扩展；软件约束外部master不碰锁字不是硬件原子保证，未检测外部写的LR/SC也不能据此宣称完整A。延续m2-prep D5已有否决。本轮AMO/LR/SC继续非法、misa.A=0。后续另案审真实仲裁域/原子适配与DMA/PS旁路边界；TLAtomicAutomata名称本身也不证明全系统原子。受限实验仅可另提，不能成为默认路线。 |
| D-8 | 本阶段采用 | time CSR非法，mcounteren/scounteren.TM=0，CY/IR正常门控。标为本教学阶段支持子集，不宣称完整Zicntr；后续可MMIO映射/硬件取样/软件模拟，不必捆绑Sstc。 |
| D-9 | 采用 | 保留已验证教学ROM补丁，不动默认产物。原ROM“应当也能启动”目前为推断而非实跑结论，不宣称验证完成。 |
| D-10 | 采用视图方案，修正相关写掩码 | sstatus/sie/sip共享底层状态，sie/sip可见位受mideleg约束；sip只允许写已委派SSIP，不能改变STIP/SEIP。**但M地址mip必须有可写SSIP/STIP/SEIP软件位**，见下文。 |

## 两项必须纠正的规范约束

1. **Bare-only的SUM必须只读0。** 原SPEC把SUM存储为可写而等Sv39再生效，不符合satp.MODE固定0的条件。保留本阶段MPRV/MXR的既定语义；mstatus写全1期望改为`0x0000000A000A19AA`，sstatus改为`0x0000000200080122`（均清bit18），相应su09与字段表同步。后续Sv39任务再启用真实SUM权限功能。[官方machine章节](https://docs.riscv.org/reference/isa/v20240411/priv/machine.html)、[supervisor章节](https://docs.riscv.org/reference/isa/v20240411/priv/supervisor.html)。

2. **M写mip与S地址sip的权限不能混同。** 无S PLIC接线/S硬件定时器不取消M软件注入STIP/SEIP。增加mip[1,5,9]真实可写的软件pending状态，外部MSIP/MTIP/MEIP仍只读电平；本阶段S外部线恒0，因此SEIP读值就是软件位。未来接入S外部线时，读值OR外部线，但CSR读改写只修改软件位，不把外部电平锁入软件位。sip.STIP/SEIP仍只读，sip.SSIP仅在委派时可写；以CSR地址而非执行者当前是M还是S区分mip/sip写语义。[官方machine中断CSR定义](https://docs.riscv.org/reference/isa/v20240411/priv/machine.html)。

## 文档与验证纪律

- 不再用“v1.10–v1.12在此都相同”代替引用；为字段/异常/返回/中断表固定规范版本与具体章节，记录允许选择和有意延期的支持子集。
- su08/su09在参考机第1项退出1只说明平台配置不同，不证明后续所有检查正确。新掩码/门控/PMP缺失/软件中断须在目标实现逐项实际走到并验证。
- Rocket随机初始化敏感性是已观察事实；尚未定位具体寄存器，不能写成已确定取指权限硬件根因，更不能据“xv6通常开分页”推出板上不受影响。无需阻塞本阶段修Rocket，但报告须区分观察与推测。
- CLINT时间随执行耗时推进，带异步定时器用例不能盲目要求不同访存延迟下逐条提交完全相同；应检查合法事件顺序、结果、返回PC和次数约束。无异步事件的确定性程序仍可严格比对轨迹。
