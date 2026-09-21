# 实验执行记录

2026-09-21 实板里程碑验收：Claude执行session3，Codex只读复核。独立check-xv6.py run-1 --require-commands exit0，segments5/prompts5/stages7/fails0；同boot ebeab8a6内存预检exit0/refusals0。四命令原始输出通过，八探针标记RC0，run记录host_exit0/remote confirmed，post-health同boot/LOCK_RELEASED/FESVR0/KERNEL_ERRORS0。正式接受教学CPU替换Rocket并在PYNQ-Z1运行xv6四命令的约定目标；详xv6-board-run-3/CODEX_MILESTONE_ACCEPTANCE.md。未独立再上板，不声称usertests/性能合规；PL_RECONFIG_SAFE仍0。

2026-09-20 执行准备收口：Codex独立board-safety59/59（/tmp/codex-two-gaps-review）、transport18/18（/tmp/codex-two-gaps-transport）、deploy-bundle清单10/10均exit0；源码确认冲突expect在入dict前拒绝，生产CLI无测试锁/boot-id覆盖，测试与生产共用运行逻辑。已验收claude-xv6-board-two-gaps-ready的离线范围；详xv6-board-prep/CODEX_LAUNCH_ACCEPTANCE.md。未运行ARM、未访问或编程硬件；下一步待用户实板授权，最终冷启动后重采同boot内存证据，不能预检后重启再复用证据。

2026-09-20 验收并进入离线综合：run-v3四命令证据独立checker/变异自测通过、501哈希；不重跑长OS。板top交付binary从正确工作目录独立18/18通过exit0（首轮根目录缺probe未通过），AMO12/旧值5及DMA超时确认；ARM逻辑本机重编15/15通过，构建前隔离入口全部通过。板迟到恢复未覆盖，保留上板前门禁；授权codex-xv6-atomic-vivado-build40MHz离线Vivado，尚未执行/未授权烧板。

2026-09-20 板级差异报告复核：审RD2BoardTop/现ARM构造器及statusWord，确认旧host复位立即写1/0、未等待块设备bootRestartReady，报告寄存器表遗漏新ready/timeout位；RD2Soc存在trace开关外BDEV打印，runner有仿真专属参数。方向认可但尚不构建就绪，分派codex-xv6-board-integration有限隔离适配/生成/接口定向验证，不重开通用复位研究。未综合/上板；run-v3继续。

2026-09-20 driver有限验收：独立drive-selftest pass27 fail0、check-selftest fails0，interim哈希exit0；源码核对换行/无换行提示符、EOF排空、失败停止及退出值检查。真实run-v2本轮只读观察到shell、echo输出/返回提示符和ls提交，未独立长跑、未宣称四命令通过。详xv6-boot/CODEX_DRIVER_ACCEPTANCE.md，继续当前运行并收最终证据，不另开CPU修复或上板任务。

2026-09-20 用户要求继续：独立构造缺wc输出且无stages.txt的控制台反例，check-xv6 --require-commands仍exit0（stages0/prompts5/fails0）；pipe全局数字正则误匹配ls目录数字。已将有限driver/checker补修追加当前codex-xv6-progress-diagnosis，要求分命令证据与完整阶段/退出记录及反例自测。已有4MiB shell/echo/目录观察不撤回，未验收cat/pipe，不重开CPU设计。

2026-09-19 FENCE.I交回部分复核：独立r02在新交付t0运行exit0、276拍、零陷阱；未重编及全量重跑。哈希415/416，fs-boot3.img不匹配。run-dev2在所谓mknod阻断后仍写盘完成并于547303400再次U态ecall；不认可永久睡死/软件归因。r03存在S态执行M CSR后被通用handler跳过、最终接受cause8或9的问题，需窄修权限验证。已分派codex-xv6-progress-diagnosis，授权一致性只读仿真快照并继续shell，未验收完整xv6/板测。

2026-09-19 xv6阻断裁决：当前HASHES.txt 47项独立通过（交付声称62待对齐）；复用已验收core-run3/t0独立跑r02，实际exit2，432拍，非法FENCE.I cause2/tval100f。run6归档显示userret非法指令后陷阱帧存储页故障循环，未独立重跑长xv6。批准窄实现Zifencei及可选4MiB仿真，要求真实后端自修改代码/监视器验证；分派codex-xv6-fencei-resume继续启动，纠正userret不等于U态成功、设备几何不等于读完4000扇区。未到shell，未综合上板。

2026-09-19 R-BOOT写目标修复有限验收通过：227哈希独立通过；注册codex-rwt-review2使用交付A模拟器完整重跑八场景与missing-READY反例，RBOOT_DONE fails=0 infra=0、入口退出0；首次启动未保持存活不计证据。写受理18951→hold18952，完整磁盘/重启读回通过；新读负例独立以write-target重查退出1。默认/V1、全SoC及原子排空本轮审归档，未重编、未声称历史build3重测。详rboot-write-target/CODEX_REVIEW.md。CPU-A有限收尾完成，分派codex-xv6-teaching-boot最小PMP适配和真实shell/小程序仿真，未综合上板。

2026-09-19 CPU-A收尾有限复核：999/999哈希独立通过；归档a01-t0独立checker得138例/72组合通过，rc3与缺完成签名均拒绝。审A使能构建参数及完整回归归档，未独立重编全跑。本轮认可收尾2/3，g2仍不通过：原始日志显示失败在epoch1初次扇区2读后、首次写前重启，旧build3的6404失败同样如此；通过记录实际在12878写请求后hold，而非配置阈值9000。分派codex-rboot-write-target-fix，明确授权隔离测试/触发窄修，不推定CPU或设备缺陷，不放宽数据和完成门禁。详cpu-a-closeout/CODEX_DECISIONS.md；下一主线xv6仿真，未综合上板。

2026-09-19 CPU-A功能主体复核认可：1611哈希；独立新构建CPU_A_DONE scenarios=15 infra=0 fails=0且正向实际退出0；交付SoC boot12及A/NOA探针独立重跑通过。未独立生成SoC或重跑RBOOT全套；g2-write-inflight已报告失败不能豁免为通过，根因未确定。分派codex-cpu-a-closeout恢复g2、强制正向退出并补新A配置/SoC旧程序回归，详cpu-a/CODEX_REVIEW.md。未综合上板，xv6未启动。

2026-09-19 CPU原子后端收口：1720/1720哈希；交付run10二进制27场景独立重跑，19正向0/0、8负向score1；14自测通过，原CPU_REQ错AMO/operand反例现在明确拒绝。审完整请求映射与D先于CPU响应校验，未独立重编或重跑旧V1/M3。裁决详cpu-atomic-backend/CODEX_REVIEW_3.md。已分派codex-cpu-a-integration完整A接入核及隔离R-BOOT配置；xv6启动另案，不综合不上板。

2026-09-19 原子后端第二次验收：1216哈希，run8交付二进制24场景独立重跑吻合，九日志自测通过。R2/R3及原R1问题局部认可，但新定向证据显示CPU_REQ改AMO或operand仍通过，TL映射未绑定完整CPU语义。见cpu-atomic-backend/CODEX_REVIEW_2.md，已分派codex-cpu-atomic-request-binding-fix唯一窄修。未独立重建、未进入CPU-A/xv6，不综合上板。

2026-09-19 CPU-A后端首次复核：607/607哈希；交付二进制14场景重跑吻合（未重建）。独立missing-d/wrong-cpu-data/missing-cpu-response三日志反例皆score0，验证链未覆盖CPU返回及闭合。源码确认拟定Broadcast后查teaching-phys不匹配，原子能力判断不是DRAM白名单，缺D/CPU响应背压、读成功写失败门禁。裁决阶段暂不通过，OPEN codex-cpu-atomic-backend-fixes，详cpu-atomic-backend/CODEX_REVIEW.md。不进入CPU-A或xv6实施。

2026-09-19 CPU原子准备裁定：52/52哈希、两审计脚本重跑、直接kernel ELF反汇编确认4条amoswap；核对PMP/A-D与实际设备树，审AtomicAutomata状态机发现读error仍进入Put，要求隔离修正。A1–A6裁定落盘cpu-atomic-prep/CODEX_DECISIONS.md，已分派codex-cpu-atomic-backend：DRAM原子/预约节点与V2桥先行，活动CPU-A与xv6后续。审计认可不等于原子实现验收，未综合上板。

2026-09-18 CPU-SV39补修后仿真验收通过：3579哈希；独立PTW四例通过；新构建完整CPU_SV39_DONE fails=0含三时序、SU、旧PTW缺陷证明；24点复位扫描通过；交付SoC模拟器boot11实际重跑退出0、启动/异常/AXI门禁通过。IM/C与SoC其他回归本轮审归档，未声称独立全跑。见cpu-sv39/CODEX_REVIEW_2.md。已分派codex-cpu-atomic-platform-contract，冻结原子与xv6启动适配实施契约；未综合上板、xv6未启动。

2026-09-18 CPU-SV39首次验收暂不通过：1929哈希、交付模拟器sv01–06独立重跑退出0；新构建PTW单元发现非叶U/A/D保留位逐位置1都错误成功（合法控制PASS，三错误例FAIL），与冻结规范保留位页故障规则冲突。见cpu-sv39/CODEX_REVIEW.md，已分派codex-cpu-sv39-nonleaf-fix窄修。尚未独立全量回归/SoC，不代表Sv39验收完成，不综合不上板。

2026-09-18 CPU-SU验收通过：2878/2878哈希；新构建CPU_SU_DONE fails=0（su01–11三时序、su12 U模式定向中断、三个具名故障）；新构建CPU_C_DONE fails=0含M2_3_DONE fails=0；交付SoC二进制独立重跑4M3/boot09/boot10/原始hello/su01/05/06，CODEX_SU_SOC_PASS。范围和日志见cpu-su/CODEX_REVIEW.md；未独立重建SoC、未综合上板、未启动xv6。已分派codex-cpu-sv39-implementation，先简明设计后直接实施无TLB串行PTW，原子与启动软件适配另案。

2026-09-18 CPU-SU准备裁定：独立210+2327哈希，C验证固化通过；重新编译SU软件并重跑Rocket/QEMU，su01–07全0/0、su08/09预期1/1、probe0/0，SU_REFRUN_DONE fails=0。随机初始化敏感性复现但未定位根因。D-1…D-10见cpu-su-prep/CODEX_DECISIONS.md：D7拒绝默认核内RMW原子方案；Bare-only SUM只读0、M写mip软件STIP/SEIP必须修订；其余按裁定边界采用。已分派codex-cpu-su-implementation，先同步再实现Bare M/S/U，无需新规划审批，不综合上板。

2026-09-18 CPU-C仿真验收通过：独立1775哈希、新构建解压49152枚举零差异、两故障明确拒绝、新构建CPU全入口CPU_C_DONE fails=0（含M2-3全回归）；复用交付SoC模拟器独立重跑4M3/M/C/原始hello成功。原IF2 IRQ注入enabled=0不足，Codex补跑enabled=1目标800001d0，真实RF x7=31000、恰一次退休先于IRQ且mepc=800001d4，两例通过；下一任务固化入口。详cpu-c/CODEX_REVIEW.md。已分派codex-cpu-su-contract：Bare阶段S/U契约与测试准备，暂不改CPU功能RTL。未综合未上板，xv6仍未启动。

2026-09-17 CPU-M两项收尾有限验收通过并分派codex-cpu-c-extension：独立1401哈希、从源码新构建三CPU时序/IRQ/乘除中复位/精确负例通过；总入口接回正确回归脚本。Codex完整入口末段M2-3构建两次遇Verilator内部线程池错误，CPU_M_DONE fails=1，明确不是全量独立通过；Claude core-run2归档完整回归通过。结合上一轮功能证据收口M，详cpu-m/CODEX_CLOSEOUT_REVIEW.md。下一步整数C及最简变长取指，不综合上板。

2026-09-17 CPU-M主动验收：独立932哈希、重编单元8022例及新种子31318例通过，CPU三内存配置/两IRQ/两具名负例与I对照、原4M3和新增M SoC程序重跑通过。功能主体认可；完整M2-3本轮只审归档，CPU/SoC用交付二进制。发现总入口未接回已修回归脚本及CPU级长运算复位验证缺失，已分派codex-cpu-m-closeout两项窄修，详cpu-m/CODEX_REVIEW.md。未综合上板；用户明确后续交付主动验收并继续协调，不再等待催办。

2026-09-17 R-BOOT超时补修限定验收通过：注册codex-rboot-review2，独立499/499哈希；交付build3模拟器重跑全部冻结门禁和原4项M3均通过。晚恢复205973 TIMEOUT→261610 LATE_DRAIN ready0，释放/重载均0；源码硬件rbFailed与host R_FAILED锁存符合契约。未独立重新编译、未注入伪READY、未综合上板，默认归档RTL哈希28ec3c91不变，PL_RECONFIG_SAFE仍0。报告restart-boot/CODEX_REVIEW_2.md。下一任务已分派OPEN codex-cpu-m-extension：完整整数M迭代实现，C另案，保持多周期单口；fix13待有限复核及其他延期项不因此自动通过。

2026-09-17 R-BOOT有限验收：独立284哈希、原故障修复/全缓冲核对、读写DMA/排队完成、三轮重启及永久卡死/删READY反例复现通过。正常受控重启修复认可；仅余超时fail-stop契约缺口：硬件超时后设备晚恢复仍可READY，host打印一次超时后也未禁止后续释放（源码/生成RTL确认，尚未动态跑晚恢复）。已分派codex-rboot-timeout-failstop窄修两处并补一晚响应例，不重启通用矩阵研究、不综合不上板。报告restart-boot/CODEX_REVIEW.md。

2026-09-17 用户授权重新聚焦并分派：主线计划顶部更新，新增OPEN codex-rboot-bdev-clean-restart交Claude，先修已复现bdev跨重启旧完成/DMA污染问题，以三个实际状态、连续三轮启动、一个不完成负例及原4M3回归为冻结门禁。通用旧D/重复写注入、精细复位窗口和PL热重配置移出关键路径，不标为通过；fix13两项补修仍待Codex有限复核。后续推进整数M/C→特权/Sv39/原子契约→xv6，当前只授权隔离实现仿真，不综合不上板。本条记录分派，非实现/验收完成。

2026-09-17 RD2第五轮未收口：独立1673哈希、16checker/18runner探针通过，新negative入口补修认可；独立编译生成RD2Throttle最小测试证实30/200拍延迟首拍旁路、背压时下一拍撤valid。删除reset-after-apply已接受写的AW/W/B仍checker0，zero/one均通过不符合接受后恰一次。已分派codex-rd2-throttle-and-discard，先修延迟单元/守恒判据再跑矩阵；本轮未重跑完整SoC套件，不综合不上板，bdev故障未修复。详CODEX_REVIEW_5。

2026-09-17 RD2第四轮后端验收仍部分认可：注册独立任务完成1111哈希、4 M3、11正向+fault3实际负向、16checker/14runner复现。新增单调时序的额外AXI写与超范围strobe仍误通过；run_negative吸收exit124。DDR场景复位发生在CPU写之前，尚不能证明复位中写恰一次。已分派codex-rd2-backend-bijection-matrix，要求双向归因/真实写故障与复位边界有限矩阵/所有runner路径基础设施检查。D已有bdev陈旧完成故障探索，未修复，SAFE0；未综合上板。报告CODEX_REVIEW_4.md。

2026-09-17 RD2第三轮：独立820哈希、4个M3启动、11正向场景及15checker/14runner探针通过；认可ROM/ELF读数据判据、旧三对照反例修复和逐轮reload检查。仍未闭合后端写exact-once/实际旧响应错配证据：重复DDR写请求+响应仍误通过（模型78→79写），CPU日志模型不观测后端副作用且跳过复位丢响应写。分派codex-rd2-backend-exact-once窄补实测，不重做已认可项；A/B/C仍部分认可，D待做，无硬件操作。见RD2 CODEX_REVIEW_3.md。

2026-09-17 RD2 A/B/C第二轮部分认可：独立485哈希、4个M3启动、10个场景、11 checker+11 runner探针通过；600拍SAFE稳定、msip入口脉冲修复和三次host重载再唤醒/一次最终完成复现。仍有数据半字交换/错误位/非取指数据误通过、无注入legacy失败误判、reload时序未绑定轮次。已分派codex-rd2-oracle-final-gates，仅补独立oracle与门禁，不重做已通过RTL；D未启动，不综合不上板。见RD2 CODEX_REVIEW_2.md。

2026-09-17 RD2 A/B/C部分认可、暂不整体验收：独立218哈希、4个M3启动、6个定向场景、11个既有探针通过，拆域网表与默认RTL哈希核实。新增6种日志破坏仍误通过；legacy模拟器不存在仍总门禁exit0；实际600拍保持复位暴露SAFE每256拍回绕。已分派codex-rd2-abc-corrections修验证链/状态并补应用启动后host重载再唤醒仿真。RD2-D未完成、PL_RECONFIG_SAFE保持0；本轮不综合不上板，原50ms条件不变。详见reset-drain/rd2/CODEX_REVIEW.md。

2026-09-16 用户要求分派，已发布OPEN codex-rd2-soc-reset-drain给Claude：实验SoC分域复位/CPU与全局quiesce分离、TSI/bdev与AXI部分写排空、独立定向模型和M3全链路仿真。授权隔离实现/生成/仿真，不Vivado或硬件；默认板级配置保持，≥50ms现行条件不取消。本条仅分派，RD2未完成。

2026-09-16 RD1最终验收通过（隔离桥单元范围）：本轮逐字提取真实生成门禁独立四组合通过，完整1457项身份清单核验exit0；结合上轮32模拟器与18故障探针，前两轮阻断收口。报告RD1 CODEX_REVIEW_3.md。本轮未重编译/硬件操作；RD2待分派，M4-c原50ms操作条件不变。

2026-09-16 RD1补修部分验收：独立32二进制结果符合预期、18故障探针全拒绝、完整HASHES通过，同拍复位及上轮三漏洞补修认可。仅剩生成入口保存genrc但不判定、失败留RTL仍继续的源码缺口，分派codex-rd1-generation-exit-fix，不要求重做RTL。报告RD1 CODEX_REVIEW_2.md；未重编译/硬件操作，RD2仍未启动。

2026-09-16 RD1暂不收口：独立28模拟器复现19正向/9旧对照，HASHES核验通过；删除全部WRITE_APPLY、删除结束记录、CPU响应err翻转三反例均误score0，runner还会掩盖对照构建失败。已分派codex-rd1-validation-fixes，补写应用因果/错误匹配/完整结束/runner状态及同拍复位边界。报告reset-drain/rd1/CODEX_REVIEW.md；未重编译或硬件操作，RD2未启动。

2026-09-16 用户要求继续至明确分派：审查RESET-DRAIN-SPEC第二稿后，分派OPEN codex-rd1-bridge-drain-unit，实施隔离桥侧soft-reset/pending-A/排空及独立定向仿真。全局方案仍有短脉冲D1复位漏失、瞬时空闲不等于PL安全等待定项，RD1不接生产SoC、不改板级配置、不Vivado/板测。交付后独立验收再推进RD2。

2026-09-16 复位/排空方案初审：采纳分域保留事务记录方向，但未握手A、部分AXI写、TSI/bdev全局排空与QUIESCENT范围、reset同拍优先级及跨epoch判据未闭合。已分派codex-reset-drain-spec-revision只做方案/测试规格补证，不直接修改RTL，不Vivado/板测。当前M4-c条件化通过及50ms操作要求保持。

2026-09-16 M4-c限定验收通过：独立读取session-5原始console四项标记/exit0及Rocket回退hello PASS/exit0，三份资产HASHES核验无错误。条件为attempt-2修复桥与每次运行前保持复位≥50ms；无保持仍竞争，不宣称复位语义完整解决。报告m4-board/CODEX_REVIEW.md；本轮未连接板卡、未重跑仿真/硬件。下一步优先复位/排空设计与定向测试方案，不直接扩展ISA。

2026-09-16 用户明确授权继续M4-c，已分派OPEN codex-m4c-first-board-tests给Claude：独占板/串口，核验教学及回退镜像后PL加载，marker→DDR→CLINT→badaddr限时裸机测试，首错停止，结束恢复Rocket并验证hello。澄清旧runbook自租约冲突（先离线preflight再claim并复核）和单串口读者要求。不改SD/PS镜像，不扩展xv6；本条仅分派，未实际编程或板测。

2026-09-16 M4-b离线构建验收通过：原始工具状态综合/位流完成，40MHz WNS+2.826ns、WHS+0.031ns、TNS/THS0；LUT9149/17.20%、FF3849/3.62%、BRAM/DSP0。独立12源+8产物哈希/大小与实际源集合通过，报告checker pending2/pass0，教学/回退bit-bin数据对应核实。见m4-build/CODEX_REVIEW.md；本轮未重跑Vivado或访问硬件。下一步M4-c板测待用户另行授权。

2026-09-16 用户在M4-a通过后回复“继续”，授权推进M4-b离线实际构建；已向Claude分派OPEN codex-m4b-vivado-build，独立工程封存输入→综合→实施/位流→40MHz资源时序/CDC/DRC审计→产物身份交付。仍不授权板卡/JTAG/串口/烧写；本条仅任务分派，不表示Vivado已启动或构建成功。

2026-09-16 M4-a最终验收通过（仅上板准备）：独立153项哈希全部OK，完整自测68/68退出状态与诊断符合预期、exit0；证据m4-prep/codex-review-3-tests，报告CODEX_REVIEW_3.md。上轮四项准备门禁补修收口。未重跑CPU仿真/生成RTL、未Vivado/硬件；下一步M4-b真实构建需另行授权，板测M4-c仍独立授权。

2026-09-16 M4-a二次验收：独立dryrun0/拒执行3/注入失败1、真实报告pending2/测试声明pass0、有效资源遮蔽反例1；认可Top shim与主要门禁补修。仍复现必需身份/状态字段与跨时钟表缺失误PASS；自测一项SyntaxError被缺文件错误冒充通过；哈希清单混用路径根，构建源身份未与产物清单绑定。分派codex-m4-prep-final-gates，报告m4-prep/CODEX_REVIEW_2.md。未运行Vivado/硬件或重跑CPU仿真。

2026-09-16 M4-a部分认可，暂不收口：独立板RTL审计正例0/旧反例1；复现审计失败被管道掩盖、资源200%报告仍通过。原wrapper实例Top而新模块TeachingBoardTop，构建入口错误建议更换整个板级top，层次未闭合。当前preflight正确拦截，但身份/缺件/占用门禁需窄修。已分派codex-m4-prep-corrections；详见teaching-cpu/m4-prep/CODEX_REVIEW.md。本轮未重跑CPU仿真、未Vivado/上板。

2026-09-16 用户授权分派M4-a首次上板准备：OPEN codex-m4-board-preparation，教学板级Top/接口与复位审计、结构性关闭注入、独立生成与仿真、资源时序/板测/回退清单。本轮不运行Vivado、不碰板串口。同步澄清租约：资源密集构建归vivado；JTAG/hw_server硬件访问归board；离线只读报告不占板，租约不等于硬件操作授权。

2026-09-16 M3最终验收通过（旧SoC/RV64I启动仿真）：新AXI因果checker独立重放11日志通过，18探针全部符合期望，原R/B移到cycle0漏洞独立拒绝；最新8项CPU事件门禁和74项身份核查通过。自查重复记录4探针拒绝，M2-3增强checker旧证据仍通过。结合历轮独立SoC/退出专项，M3收口，报告m3-axi-review/CODEX_REVIEW.md。本轮未重编译/重跑硬件仿真，下一步首次上板准备，尚未授权Vivado/烧板。

2026-09-16 M3 run-b退出专项独立通过：sim3四模式退出0/3/0/0，错误响应由checker拒绝；命中真实exit_store，延迟尾部1887周期，74项哈希通过。AXI尚余因果门禁漏洞：全部R或B移到cycle0仍checker0，已分派codex-m3-axi-causality。报告m3-fixes/TAIL_CODEX_REVIEW.md；未重编译/上板，M3尚未最终收口。

2026-09-16 M3补修暂不收口：独立marker对照/withhold/error退出0/2/2，15探针全部拒绝、72哈希通过。但tail拦截的是控制台首字符写PC0x80000040，而非exit_store0x80000084，未测试host候选成功后的尾部；AXI仍仅总数未逐burst/ID门禁。已分派codex-m3-tail-target-fixes。证据m3-fixes/codex-review-Aevj6g，未编译或上板。

2026-09-16 M3首次验收暂不收口：独立4程序×2时序退出0，原ROM异常启动复现，69项身份核验通过。四项日志变换（重复/孤立RESP、无AXI、无MRET）checker仍通过；退出store专项被首次取指丢响应替代，runner遗漏2/8事件检查和自身快照。已分派codex-m3-validation-fixes，报告m3/CODEX_REVIEW.md、证据codex-review-ptWiWx。未重编译或上板；首次-s参数被fesvr拒绝的日志原样保留，以无该参数重跑为准。

2026-09-15 M3 ROM阻碍已裁定方案A：独立核对镜像哈希/偏移0x54字0x30301073及CSR默认非法，批准仅教学配置替换为NOP、保留原Rocket ROM，不加mideleg。要求生成脚本输入校验、实际RTL/resetVector复核、原ROM非法陷入负例与修正版真实MSIP启动顺序。注意原ROM已设mtvec，不应未经运行称“停在第六条”；CLINT空洞行为仍待实测。详见teaching-cpu/m3/ROM_DECISION.md。本轮未修改ROM或运行启动仿真。

2026-09-15 用户授权分派M3：OPEN codex-m3-soc-boot给Claude，教学CPU薄封装复用M1桥/单口，先实际ROM审计，再真实TSI→MSIP→ROM→RV64I DRAM程序、HTIF退出及CLINT闭环；补逐笔事件/完成尾部门禁与背压测试。旧版本/原Rocket保留，不引入M/C/A，不上板。此次仅分派，M3尚未运行。

2026-09-15 M2-3最终验收通过（独立CPU中断/安全边界范围）：独立6链+2store正向、3负例25/23/5及12基础回归通过，四程序跨延迟完整轨迹一致；两个归档checker与167项身份校验通过。真实重复apply、目标store限定、固定目标IRQ前退休及真实RF读回补证已成立。证据m2-3-events/codex-review-qlQgXM，报告CODEX_REVIEW.md；未重新编译、接SoC或上板。逐笔总线事件日志留下一阶段增强，不宣称已经具备。下一步旧SoC集成仿真。

2026-09-15 M2-3补证仍未收口：独立六项en矩阵、三项watch正向及重复写负例退出符合报告，两个归档checker通过、140条身份校验通过。但DUP_STORE仅改计数未重复写事件，watch实际注入load而非store，退休统计用整场累计且ARCH目标取错。已分派OPEN codex-m2-3-event-evidence-fixes，报告m2-3-fixes/CODEX_REVIEW.md，证据codex-review-IJQCkN。认可已使能六点注入改进；未确认正常RTL新故障，未重新编译或接SoC/上板。

2026-09-15 M2-3暂不最终验收：独立15项IRQ正向、3项故障（5/3/19）、3项t01回归符合预期，归档checker/源码/ELF/48条模拟器身份校验通过。发现五类i01均在MIE开启后同一PC/周期接受，实际fire发生于未使能初始化阶段；另store最终值与req==resp不足以证明目标store恰一次。已分派OPEN codex-m2-3-coverage-corrections窄修验证链，报告m2-3/CODEX_REVIEW.md、证据codex-review-R0lclM；未确认正常RTL故障，未重编译/接SoC/上板。

2026-09-15 按用户新路线分派M2-3：OPEN `codex-m2-3-interrupts`，实现三路M中断、mie/mip、电平语义与架构更新落地后的安全接受边界，WFI为NOP；在途取指/数据请求不得取消，定向覆盖各等待阶段。保留后补M/C结构但不实现扩展；接下来SoC/RV64I首次上板，M/C后置。此次只分派，未运行或上板。

2026-09-15 M2-2验收通过（限定M-only CSR/同步异常/mret）：独立15正向、9专项、3新增故障符合预期；五程序三延迟完整轨迹一致，无协议/观测错误，源码/模拟器/C++/ELF哈希通过。未知参数独立拒绝；其余全量门禁核查归档checker。报告m2-2/CODEX_REVIEW.md，证据codex-retest-GMBmLR。未重编译CPU/接SoC/上板，下一步M2-3待分派。

2026-09-15 用户授权分派M2-2：OPEN `codex-m2-2-csr-traps` 给Claude直接实现M-only CSR/同步异常/mret与真实计数器，mtvec direct、无C mepc低2位归0、mret正常退休、陷阱不退休、CSR真实读回交叉验证。未知参数静默忽略修复并入本轮。旧run-f保留；不接SoC/上板、不实现外部中断/C/MMU。

2026-09-15 M2-1补修验收通过：独立12正向、跨三延迟完整commit轨迹、3 ROI、原非法JALR及funct3=1..7、load载荷正常/泄漏、尾部error/drop及cycle/minstret边界符合预期；源码/模拟器哈希通过。证据m2/codex-fix-review-8Euvjx，报告m2/CODEX_REVIEW.md。未重编译CPU，旧故障本轮通过归档checker核查；尚未完整M-mode异常返回、SoC或上板。下一步M2-2。

2026-09-15 M2-1首次验收未通过：12正向独立复现、run-e checker通过，但新非法JALR funct3=001反例实际正常跳转无trap；另查到load wdata未清零、tohost在响应/退休前结束（req/resp差1）、cycle读伪返回0及完整跨时序提交轨迹未比对。已分派 `codex-m2-1-corrections`，报告m2/CODEX_REVIEW.md，证据codex-review-zEH7QY。未重新编译CPU或上板。

2026-09-15 M2准备补修验收通过：Codex独立重编译/参考运行12 ELF（10正向0、2反例1）、49条静态ROI轨迹及非空目录拒绝通过。边界CSR计数/固定misa/取指过取等语义澄清已列入m2-prep/CODEX_REVIEW.md。已直接分派 `codex-m2-1-execution-core`，授权独立RV64I多周期RTL与harness，12正向组合及CPU级故障对照；不接SoC/上板，完整CSR/MMU/原子仍后置。

2026-09-15 M2-a0部分验收：Codex独立重编译8个ELF并在Rocket参考模型全部通过，M1-soc四个合成负例通过。批准Verilog薄封装、迭代乘除、后续整数C和无TLB起步方向；拒绝无保护PMP伪实现及本地RMW当正式A。规格需窄修PA越界、退休/陷阱语义、CSR阶段及可执行参考退休门禁/x0反例，已分派 `codex-m2-prep-contract-fixes`。详见m2-prep/CODEX_REVIEW.md；CPU RTL尚未授权实施。

2026-09-15 已按用户要求分派M2-a0给Claude：`codex-m2-spec-and-test-prep`，最简RV64多周期核规格、ISA/CSR分期、关键决策建议、实际裸机测试编译/参考运行与下一实现任务清单；同时窄修M1-soc版本记录/AXI闭合自动门禁。此阶段不授权完整CPU RTL或上板，待规格验收后直接进入首个执行核实现任务。

2026-09-15 M1无CPU旧SoC集成仿真验收通过：Codex独立basic/backpressure各768笔零错误，AXI AR/R=315、AW/W/B=443闭合；fault-payload退出1命中84项数据错误，200周期超时退出2。三级哈希通过，M1-b修改后13例独立回归符合预期。见 `teaching-cpu/m1-soc/CODEX_REVIEW.md`；未重新编译/上板，不代表CPU、HTIF/DMA并发或xv6完成。下一步细化M2规格与裸机任务。

2026-09-15 用户批准下一步并要求分派：已向Claude发布 `codex-m1-soc-integration`，无Rocket测试配置内验证事务发生器→req/resp桥→旧TL→AXI4→SimAXIMem。采用仿真done/failed判定，保留原Rocket/外设与板级边界；要求AXI侧实际事务证据、背压/错误与故障对照。仅分派，尚未接单/运行；不跑Vivado或上板，不启动M2。

2026-09-15 M1-b补修验收通过：Codex独立重跑13例（5正向、8定向负向），零延迟两例各694笔同拍A/D、704笔完成，旧桥死锁对照复现；valid撤销/载荷改变均被专属checker拒绝。13例源码/RTL/二进制哈希核验通过，run-sim受控失败返回2。详见 `teaching-cpu/m1/CODEX_REVIEW.md` 与 `codex-fix-review-zbEfhK/`。M1-a/b已通过；未重新编译、未桥SoC集成或上板，下一步旧SoC事务发生器集成验证。

2026-09-14 M1-a验收通过，M1-b退回窄修：Codex独立重跑hello（rc0、6861周期）及桥3正向/5反例，均复现交付。源码审查发现sA不接收D可能与零延迟RegisterNode互等（尚未RTL复现）；测试后端均minLatency=1，且resp保持checker漏检临时valid撤销。已分派 `codex-m1-bridge-corrections`，同时补unsupported-size覆盖和run-sim退出码传播。证据/边界见 `teaching-cpu/m1/CODEX_REVIEW.md`；未重新编译、未重跑xv6、未集成桥SoC或上板。

2026-09-14 调度检查：无新实现待验收，Claude待命请求M1/M2分派。Codex已冻结 `teaching-cpu/PHYSICAL_PORT_V1.md`，分派 `.coord/proposals/codex-m1-simulation-bridge.md`（M1-a环境判定→M1-b旧TL桥/测试器）；等待接单。M2架构候选未整体批准，不阻塞M1。本轮仅计划/契约变更，未运行桥测试或上板。

2026-09-14 M0补证验收通过（平台审计范围）：Codex独立核对BootROM/生成RTL复位PC、zynq_driver→htif.start→tsi.reset启动链，以及旧TLBundleD.error和Get/Put API；前轮三项错误已修复。报告 `teaching-cpu/m0/CODEX_REVIEW.md`。补充SUM只放宽S对U页数据访问、不放宽取指；启动reset操作不等于证明外部AXI空闲。CONTRACT仍是候选规格，M1物理接口/M2架构设计项待明确；mtime频率和旧仿真环境待实测。未构建/上板，允许进入下一阶段任务细化。

2026-09-14 M0首次复核：审计已交回，Codex核实平台控制台为HTIF/TSI、现有RV64/sv39移植及软件A/D处理。但启动和TL契约有实质错误：实际resetVector为0x10040（非ROM基址0x10000），zynq_driver构造函数先释放sys_reset而非ELF加载后释放，旧版TLBundleD使用error而非denied/corrupt。已分派 `.coord/proposals/codex-m0-contract-corrections.md` 修正M0文档及证据；尚未冻结CONTRACT，不启动M1桥或M2核实现。本轮只读核对，无构建/上板。

2026-09-14 主线调整：用户批准优先最简教学CPU替换现有Rocket运行PYNQ-Z1/xv6。RW13尚未接单且coord无运行作业/租约，已延期、撤下执行优先级，原任务书保留。新主线 `TEACHING_CPU_XV6_PLAN.md`；M0已分派Claude（`.coord/proposals/codex-m0-rocket-replacement-contract.md`），先只读审计板级版本/ISA/特权/MMU/启动/外设/TL-AXI接入点与最小内存契约，再由Codex核验并分派M1/M2。当前未更改CPU/板级源码或运行硬件测试；此前实验完成记录不变。

2026-09-14 总进度与下一项：协议/计数/身份验证基础及RW10–RW12限定实验已验收；当前重心从延迟注入转向正交端口组织。RW13已分派，等待Claude接单（`.coord/proposals/codex-rw13-port-organization.md`）：冻结conf.ports=1与核心/master路径，用独立scratchpad端口参数比较统一/双口×S0/2/8，目标96条主矩阵。源码中conf.ports改变dpath，故禁止直接切原生ports当作纯后端对照。队列/核心多在途、其他流水核心统一接口、实际LUTRAM/BRAM/DDR/资源时序和系统应用对比仍未完成；现有Rocket/PYNQ/xv6作为已有参考资产，不计为新实验已完成。任务相关源码写入权交Claude，本文与总方案仍归Codex。

2026-09-14 最新验收：RW12 已收口。Codex 独立复核修正版 `rw12-matrix-20260914T154245Z-fixedmeta` 64+12+3 的日志/哈希/构建身份通过；未展开类名与类名互换反例正确拒绝。诊断样本2+3核验通过、五个样本事件数等于最终reqs/resps；FIFO TB S0-depth2-be3、S0-lfsr、S8-strict独立重跑通过，双在途定向例逐笔延迟4拍。新S8 ALU32独立运行结果一致、响应计数407闭合。独立证据 `counter-baseline/results/codex-rw12-fixes-4ipc8fay/`；脚本 `counter-baseline/scripts/codex-rw12-fixes-review.py`。Claude42项负向归档已审，本轮未重跑全42项。核心/适配器功能未改，相关源码写入权已交回Codex。

RW12边界：S={0,2,8} 是共享scratchpad服务模型整体比较（延迟与吞吐耦合）；未测共享边界ROI事务数/等待拍数，不能从受bootrom影响的全程序计数差分推导。旧元数据与旧更新前快照保留，当前身份验收使用fixedmeta；多在途TB时延以修正后的FIFO测量为准。BRAM/DDR、端口组织和核心多在途仍待后续实验。

2026-09-14 RW12交回复核：完整64+12+3日志/哈希检查通过；Codex独立S0/S8 × ALU/STORESEQ规模32四次运行与归档一致、协议零事件，S8-strict/S8-contend归档TB重跑通过。结果 `counter-baseline/results/codex-rw12-kco319ge/`。功能/性能数据限定认可，最终验收待 `.coord/proposals/codex-rw12-review-fixes.md`：S2/S8配置类名模板未展开；共享计数为响应握手更新前快照（如453行事件最后resps=452）；S0多在途TB的单时间戳时延测量需限定或修正；移除被bootrom污染的ROI计数差分表述。已授权Claude窄补修，无需重跑整矩阵。

2026-09-14 下一任务已分派：RW12 共享 scratchpad 后端延迟，任务书 `.coord/proposals/codex-rw12-shared-backend.md`，等待Claude接单。固定HoldIDMMIOIrq单端口核心，在scratchpad仲裁后插入独立可选延迟模块；先共享链TB/redirect验证，再三点性能矩阵。尚未实现或运行。任务相关源码写入权交Claude，本文与总方案仍由Codex维护。

2026-09-14 最新验收：RW10 中断交错与 RW11 固定 HoldIDMMIOIrq 核的 D 口接受等待/响应延迟矩阵已收口。RW11 最后三项门禁经 Codex 独立复核通过：完整矩阵、新旧档核验各160+30+3，R补点96+18，原八项反例全部按正确理由拒绝。证据 `results/codex-rw11-v2-ed6hkm1i/`（相对 counter-baseline）。本次重解析日志、核对哈希与反例，未重建 RTL；此前八次独立SoC抽样和两个TB仍作为执行证据。结论仅覆盖固定核的D路径注入，不代表全内存、BRAM或DDR。以下按各次发生时间保留历史状态。

2026-09-14 接管复核：Claude 已交回且无租约。HoldD 的R1 55条、B第二轮64行、lat2/7共24运行和修正后SV 318/0等价证据限定验收；RW9首次总作业exit1不作为整体通过，其两个已解释门禁问题分别核对。Codex用交回模拟器独立重编译并运行timer四项全部PASS，结果`codex-rw6-timer-UXiKne`。新增HoldDMMIOIrqLat7与RW9IRQ DEFER/TAKE逐拍观测；首轮只因runner环境set-u失败，已修正并注册`codex-rw9-irq-defer2` PID967683，RTL结果待定。1-stage、外部/软件中断未纳入此次三级保持型里程碑。

2026-09-13 RW7十二项三配置性能对照全部完成，CODEX_RW6_REVIEW_OK，见 [RW7报告](counter-baseline/CODEX_RW7_REVIEW.md)。HoldID整机五项通过，但IRQ仍未通过。新增独立MMIO请求快照修补配置，注册RW8作业933240构建中，目录rw7-holdid-PacTJb；旧配置及归档保留，未宣称修补通过或里程碑完成。

2026-09-13 RW7整机：`rw7-holdid-EJBfkT` 已完成构建，mr3/calib_alu_64/mmio1/excep4/branch50五项签名与协议检查通过，RW7_HOLDID_SMOKE_OK。三配置ITERS96性能作业`codex-rw7-performance` PID931568运行中，结果`codex-rw6-SCyUOB`；已完成ALU基线/HoldD/HoldID cycles=959/959/3076，LOADUSE=1535/1535/3364，instret均773，其余待完成。新增中断诊断：`codex-rw6-timer-JKaLAb`四项均99（使能读回通过，最终MTIP=0）；`codex-rw6-timer-l41bMk`四项均101（mtimecmp高字写零后读回非零）。原配置/HoldD共同复现，尚不能定位到单一RTL原因；master_adapter存在使用未锁存fcn/address与LoadGen宽度等需核查点，未修改。完整里程碑仍未完成。

2026-09-13 RW7重跑：`results/rw7-holdi-89xjhG` 五项全部符合预期，FETB_DONE fails=0。定时redirect新增相位10/15，40次redirect覆盖等待接受24次、等待响应16次，200次序列检查零错误；注错对照sequenceErrors=1且exit1，按预期拒绝。旧失败归档保留。注册作业codex-rw7-retest PID927041已进入HoldID整机构建，目录`results/rw7-holdid-EJBfkT`，宿主确认Java构建活跃；整机结果尚未产生。性能复验入口增加可选配置/模拟器目录参数，默认RW6对照不变；HoldID检查全部PROTO，尚未运行性能比较。里程碑未完成。

2026-09-13 22:07 UTC RW7接续：宿主进程表确认前端等待作业PID915190仍活着，沙箱coord显示done不能据此清理。追加注册 `codex-rw7-soc`（PID917448），仅见前端明确 `FETB_DONE fails=0` 且取得构建租约后运行新的HoldID五样本整机smoke，检查退出签名与全部PROTO告警。两个新脚本bash语法检查通过；前端/整机尚无RTL运行结果，不能计完成。

2026-09-13 RW7进行中：用户告知Claude无token并要求Codex继续，源码任务已接回。新增独立 HoldID 配置与 holdInstructionRequest 参数；I前端采用 idle/offer/waitResponse/deliver 单事务状态，redirect 保留请求并排空旧响应，禁止响应与新请求重叠。新增请求稳定断言、定时连续redirect覆盖及保持配置序列正负测试。`git diff --check`、runner `bash -n` 通过，尚未编译/仿真通过。注册作业 `codex-rw7-holdi`（日志 `.coord/jobs/logs/codex-rw7-holdi-20260913-220143.log`），等待Claude构建租约22:30:55 UTC到期后自动claim并运行五项TB；不根据PID接管。整机HoldID、性能及中断边界仍待验证。

2026-09-13 RW6：用户已批准独立配置实施；Codex 的 HoldD 改动由 Claude 接续构建并完成 smoke/回归。Codex 工具重试成功，新编译 ITERS=96 的四种基准、两配置共八项独立复验通过，周期逐项相同，HoldD 无 D 协议告警。新增计时器诊断四项均以 tohost=93 失败（原配置与 HoldD 相同），中断边界尚未验证，不能宣称完整保持型 CPU 完成。见 [RW6复核](counter-baseline/CODEX_RW6_REVIEW.md)。构建租约仍由 Claude 持有，已通过 OPEN 提案请求交回；以下为历史记录。

RW5 PC序列验证完成：三项重新构建用例sequenceErrors=0；测试端PC/指令一致错配注入使旧配对检查仍0、新序列检查1并按预期exit1。见 [PC序列结果](counter-baseline/RW5_PC_SEQUENCE_RESULTS.md)。[核心分步方案](counter-baseline/RW5_IMPLEMENTATION_PROPOSAL.md)已具备评审条件，尚未改核心功能，下一步需批准独立配置实施。

RW5直接取证完成（2026-09-13）：新RTL撤回store精确读回覆盖13/10次，整轮通过；新单端口mr3诊断正常结束，12次D口撤回全部对应无RAW/异常/flush时hazard跨拍反馈。见 [证据](counter-baseline/RW5_DIAGNOSTIC_RESULTS.md)。只加测试与opt-in观测，未改核心功能。I口PC/epoch验证及保持状态实施仍待后续。

2026-09-13 RW5接续：用户授权Claude limit期间Codex接手；已记录任务级写入权回收。独立仲裁日志checker接入runner，6组单元测试与9份RW4仲裁日志复核通过；拒绝空矩阵/残缺参数和覆盖已有目录。见 [保持边界草案与进展](counter-baseline/RW5_HOLD_BOUNDARY_PLAN.md)。核心RTL未修改；core-01新增门控经源码检查均冗余，尚需D口逐拍取证，整机保持型未完成。

最新验收（2026-09-13，RW4）：限定交付通过——core-03、受约束router/脉冲回退、仲裁多在途与读回已复核；14个归档TB独立重跑复现预期，R1/B归档checker通过。不可撤回整机仍未完成。见 [RW4验收](counter-baseline/CODEX_RW4_REVIEW.md)；下一委托 `codex-rw5-hold-boundary-plan` 为窄方案及测试门禁收口，不直接改核心。

最新验收（2026-09-13，RW3）：11个独立仲裁器归档二进制重跑复现预期，R1/B归档检查通过；不可撤回整机仍未通过（legacy撤回仍直通，strict启动依赖未合入core-03）。已批准core-03窄修并委托真实多在途、store读回及router响应保持覆盖。见 [RW3复核](counter-baseline/CODEX_RW3_REVIEW.md)，任务级授权以 `codex-rw4-core03-and-coverage` 为准。

最新验收（2026-09-13，rework2）：独立总入口的 R1、RTL 三项正向/合法对照与四项 runner 负向通过，B 归档检查通过。验证链局部验收通过；工作树仲裁器选源保持未修完，候选撤回释放锁不直接采纳为严格协议补丁。见 [复核报告](counter-baseline/CODEX_REWORK2_REVIEW.md)，已主动委托 `codex-rw3-request-contract`，不进入 B5/DDR/上板。

最新复核（2026-09-13）：上轮三个独立验收漏洞已被正确拒绝，新 R1/B 归档与扩展负向检查通过；整体仍待 RTL runner 异常退出门禁及单端口仲裁器请求数据保持修复。见 [本轮复核](counter-baseline/CODEX_REWORK_REVIEW.md)。新任务级授权以 `codex-rework2-protocol-and-runner` 为准；不进入 B5/DDR/上板。下方保留历史状态。

最新验收状态（2026-09-12）：R1、后续协议/活锁改动与阶段 B 已初审并做新规模抽样，但验证链仍有可复现漏洞，整体验收未通过。见 [Codex 复核报告](counter-baseline/CODEX_POST_R1_REVIEW.md)。已主动委托 Claude 按 OPEN `codex-post-R1-acceptance-rework` 修补验证链及 monitor 写数据覆盖，不进入下一阶段；当前任务级权限以该提案为准，以下历史分工不覆盖新委托。

开工前先在工作区根目录运行 `./coord status`，检查待决提案、资源占用和他方交接。

接口设计依据集中在 [实验方案第 3～5 节](../MEMORY_MICROARCH_EXPERIMENT_PLAN.md)：CPU I/D 分离、后端可共享；每端口 req/rsp 双 ready/valid；写地址与数据同一请求。本文保留执行历史，不把计划当成已实现能力。

## 操作顺序与验收

当前分工（2026-09-11 用户续授权）：[R1 计数修复任务书](CLAUDE_RETIRE_FIX_TASK.md) 已交由 Claude，待接单；Codex 暂停同范围实现，交回后独立验证。原 A1 已交回并复核，旧任务书中的性能 B 暂缓；连续 load 活锁另案处理。临时写入权限见 R1 第 6 节。

1. 独立源码：固定 Chipyard 1.14.0，按官方脚本初始化基础依赖和 Sodor；记录完整 SHA。
2. 工具环境：独立 Conda prefix，使用 release 的默认 Chisel 6 路径和依赖锁；记录实际工具版本。
3. 原版仿真：先构建 Sodor3StageConfig，运行 RV32 裸机 smoke test，再跑 Sodor3StageSinglePortConfig。
4. 原版基线：相同 ELF、相同测量区间，记录 cycles、instret；原生 Harvard/Princeton 比较只解释整体配置变化。
5. 协议接入：检查 Sodor 对固定延迟、stall、flush 的假设，改造可变延迟接口并加入真正的协议 monitor。
6. 可控实验：固定 CPU、内存容量和请求服务间隔，分别扫描响应延迟、端口数量、背压和队列深度。
7. 上板：先 LUTRAM/BRAM，再 PS DDR；Rocket/XV6 使用已验证版本作为独立系统级基线。

每步保存命令、退出状态、日志、配置和结果。只把通过实际运行的配置标为完成。

## 2026-09-10

- 已完成独立 clone：`/home/engineer/fpga/chipyard-experiment`。
- Chipyard HEAD：`0acc1e1de2d3284bcd4d876956932a013ffe1949`。
- tag 中锁定的 Sodor：`910a2e83ce206e86372927ec3e0b8056953f7d95`。
- 子模块初始化已完成（退出码 0）：`./scripts/init-submodules-no-riscv-tools.sh --sodor`；Sodor 实际 HEAD 与 tag 锁定值一致。
- 日志：`chipyard-experiment/init-submodules-no-riscv-tools.log`。
- 宿主机 PATH 未发现 Conda、Java、Verilator；Miniforge 已安装到 `experiments/tools/miniforge`。
- Miniforge 安装器 SHA256：`281b0ac7d550802efc81af633225a5e6116d29ae72f3ab4eae7168c3931a4c05`（下载的安装器保留在 `/tmp/chipyard-miniforge.sh`，仅记录指纹）。
- 使用 Mamba 直接读取官方 lean conda-lock 文件，安装到 `chipyard-experiment/.conda-env`；211 个锁定包，无重新求解，安装成功。
- 环境入口：`source experiments/chipyard-env.sh`，显式 unset USE_CHISEL7。
- 已检查 Sodor 源码：`MemPortIo.req` 为 DecoupledIO，`resp` 为 ValidIO，无响应 ready。
- 已确认配置类：`chipyard.Sodor3StageConfig` 和 `chipyard.Sodor3StageSinglePortConfig`，分别使用 Stage3Factory(ports=2/1)。
- 实测工具版本：OpenJDK 20.0.2、Verilator 5.022、RISC-V GCC 13.2.0、firtool 1.75.0；构建使用 project/build.properties 指定的 SBT 1.8.2（不是 Conda 的 sbt 包版本）。
- Scala 编译已成功（退出码 0，SBT 编译阶段 175 秒），日志 `experiments/sodor-compile.log`。
- libfesvr.so/libfesvr.a 已构建并安装到实验工具链；libriscv.so 正在构建，日志 `experiments/spike-library-build.log`。
- 原版 rv32ui-p-add、rv32ui-p-lw、rv32ui-p-sw 已交叉编译成功；尚未在 Sodor 仿真器运行，不能标记测试通过。
- 原生 CSREvents 只有禁用的占位事件；后续 stall/仲裁等计数需要显式实现和验证。
- DRAMSim2 构建成功；协议 HoldMonitor 已补齐，5 项 Python 测试通过，包括非法 valid 撤销和握手边沿数据替换的负例。
- 当前子模块快照：`experiments/chipyard-submodules.lock`。
- 基线运行入口：`bash experiments/run-sodor-baseline.sh`；依次构建两个 3-stage 配置，各运行 add/lw/sw；包含 1,000,000 周期超时，日志保存在 `experiments/results/sodor-original/`。
- 已启动基线运行入口；正在构建第一个 Verilator 仿真器。
- 本地已有 Python 模型测试，不等于 Sodor/RTL 已验证。先前请求保持测试仅比较两个 Request 对象，没有 monitor，不能证明请求保持规则；阶段 A 尚未完成。

## 2026-09-11：恢复冒烟与兼容性排查

- 已接收 Claude 的文件交接；确认 `libriscv.so` 已安装、双端口 Verilator 模拟器已构建。
- 复验 `ldd` 显示 `libdramsim.so => not found`；环境入口补充 DRAMSim2 运行时搜索路径后，动态依赖均可解析。
- 运行脚本改用独立时间戳目录，保留先前失败日志；记录 ELF SHA256、版本、逐项退出状态及整轮退出状态，仍然遇错即停。
- 第一轮目录：`results/sodor-original/run-20260911T053348Z-BwM5Gl/`。双端口 add 实际启动后触发 TileLink 断言：`D channel acknowledged for nothing inflight`，make 退出 2；不是测试通过，其他五项未执行。
- 源码发现：当前 Rocket `ScratchpadSlavePort` 在 `s_wait2` 推测发送请求，随后可通过 `s1_kill` 取消读或写；Sodor `SodorScratchpadAdapter` 原先只对写应用 kill，可能为取消的读产生多余响应。
- 最小兼容修改：s1 有效位由 `req.fire` 锁存，对所有请求应用 `!s1_kill`。不关闭 TileLink 断言，不改变 CPU 流水或核心访存延迟。
- 已登记 `sodor-kill-fix-20260911` 重建并运行两配置冒烟；补丁效果待运行验证。此后的结果必须标为“1.14.0 锁定源码＋Sodor adapter 兼容补丁”，不能称为纯原版通过。
- 随后该轮六个仿真子任务均退出 0，未重现断言；但我在运行期间编辑 runner 增加归档逻辑，导致旧脚本解释位置错位、收尾 EOF 错误，整轮退出 2。保留 `run-20260911T053445Z-LECb92` 及补丁快照，不作为整轮验收。已冻结脚本并登记 `sodor-verified-20260911` 重新跑完整六项。
- 最终验收目录：`results/sodor-original/run-20260911T053830Z-6dhqUN/`。两个配置各运行 add/lw/sw，六项退出码全部为 0，整轮 `exit-code.txt` 为 0；六份日志均到达 TestDriver 的 success 分支 `$finish`，无超时或断言失败。冒烟阶段通过（含兼容补丁）。
- 此轮归档了 `manifest.txt`、`source.patch`、环境和 runner 快照、`elf-sha256.txt`、`tests.tsv` 和各构建/仿真日志。目录沿用 `sodor-original` 名字，不表示没有补丁；以归档 source.patch 为准。
- 原有 Python 协议模型通过直接入口 `python3 experiments/protocol/test_reference_memory.py` 重跑，5 项通过。此前误用 unittest 没有发现测试，宿主也未安装 pytest；这两个命令不算验收证据。
- 下一阶段：先核验并定义 ROI 与 cycles/instret 的计数口径，再运行相同 ELF 的 ALU、load-use、连续 load/store 微基准。当前 `csr.io.retire := wb_reg_valid && !io.ctl.exception` 未显式排除 `wb_dmiss_stall`，须验证是否重复计数，不能直接发布 CPI。此次未修改 CPU retire 逻辑，也没有性能结论。

## 对原方案的必要澄清

以下澄清已于 2026-09-11 同步回主方案；后续接口决策以主方案第 3～5 节为准。

- “至少下一拍响应”约束针对同一请求。返回 A 的边沿可以接收 B，不能全局禁止 req_fire 与 rsp_valid 同时成立。
- 0 拍响应另设协议变体，不能放入至少一拍协议的同一合法配置集合。
- 有序多 outstanding 不需要公开 ID；共享 I/D 后端仍需内部来源队列。
- 仅锁存异步 RAM 地址，若其他端口改写同址，响应仍可能变化；须缓存响应数据或阻止冲突写。
- Sodor 不同级数并非只改变级数；改造延迟接口可能涉及控制逻辑，先记录差异再做归因。
- 延迟与服务间隔分别控制；增加 outstanding 上限仅在请求源能发出独立请求时才可能提高性能。
- CPI、等待周期可能重叠，不能将所有 stall 计数直接相加。

## 2026-09-11：设计笔记整理

- 集中记录接口选择、替代方案与代价，补充 AXI AW/W 拆分责任、写响应完成点、来源路由、取消/reset 和待冻结语义。
- 修正同拍周转、有序多 outstanding 无需公开 ID，以及原生 Sodor 不能直接任意切换响应延迟的表述。
- 区分目标接口、原生 Sodor、已验证兼容补丁和 Python 模型；没有修改 RTL、运行脚本或既有结果，没有新增性能测量。

## 2026-09-11：Claude A1 交回后的独立复核

- Claude 已交还任务级写入权，A2/A3/B 未完成。Codex 独立复核见 [A1 review](counter-baseline/CODEX_A1_REVIEW.md)。
- 双/单端口 load-100 delta=805 得到复现；单端口 mr3 不前进，诊断版最终触发 2,000,001 周期 timeout，并反复执行第三条 load。
- 正常完成的 mr2 启动阶段已直接观察 WB-stall/有效 retire 连续七拍。因此拒绝“配置中不可达”的结论；仅接受已测 ROI 内计数一致的事实，不能验收整个 A。
- 生成 RTL 核验 cycle 与 instret 计数来源；计数高字、异常/flush、自动失败检查和精确修复回归仍未完成。
- 观测补丁和结果已归档，临时观测源码已撤去，正在重建普通单端口模拟器。未实施 retire 或连续 load 的功能修复，也未增加新内存协议。
- 普通单端口重建随后成功，日志标记 RESTORE_OK。Sodor 工作树仅保留既有 scratchpad adapter 兼容补丁；诊断结果 checker 正向和启动失败负向检查均符合预期。

## 2026-09-11 R1：instret 停顿重复计数修复（claude，待 Codex 验收）

- 缺陷：`dpath.scala` 中 `csr.io.retire` 未用 `wb_dmiss_stall` 门控，而
  `reg_instret` 逐周期累加，等待 N 周期的访存被计 N 次。紧邻的 `csr_cmd` 已门控。
- 触发：`wb_reg_mem && !dmem.resp.valid`，即访问离开 tile 本地 scratchpad。
  A1 那轮 ROI 全在 scratchpad 内，结构性排除了触发区域，故读数正确而误判不可达。
- 复现：`tests/mmio.S` 在 ROI 内读 CLINT mtime。期望 4（反汇编推导），
  修复前 10（双端口）/ 11（单端口），多计量精确等于 ROI 内停顿周期数 6 / 7。
- 修复：一行，`r1-01-retire-fix.patch`。观测代码独立为 `r1-02`，可整体移除。
- 验收：`./experiments/counter-baseline/scripts/r1-accept.sh` 返回 0；
  38 条记录、必需项全中、7 项 checker 负向测试全部被拒。
- 结果：/home/engineer/fpga/experiments/counter-baseline/results/r1-final-20260911T232652Z
- 未解决：mr3 单端口活锁仍在（已知失败集合），阶段 B 仍被阻塞。

## 2026-09-12 连续访存活锁：根因、双端口修复、单端口未解（claude）

Codex 额度耗尽，用户指示继续。接 R1 之后的计划项。

- 更小的复现体：`mmio.S -DNMMIO=2`，双端口即挂死（mr3 需要单端口 + 3 条 lw）。
- 根因一（双端口）：`wb_dmiss_stall` 两项指向不同指令 —— 第一项是 EXE 里更年轻
  指令的请求未被接受，第二项是 WB 里指令在等自己的响应。退休要求两者同拍为假，
  但内存口在"接受请求"与"返回响应"之间交替，实测周期 8 拍、两事件恒差一拍，
  合取式结构上永不满足。响应只有效一拍，错过即丢失。
- 修复：锁存响应使"我的响应已到"具有粘性（`r1-03-livelock-fix.patch`，+35/-3）。
  双端口 NMMIO=2/4/8 精确给出 5/7/11，mr3/mr6 完成。
- 根因二（单端口，未修）：仲裁器用同一个 `d_resp` 位既定仲裁优先级又定响应路由。
  变长延迟下取指先 fire 清掉 `d_resp`，随后到达的数据响应被投递给指令口而丢失。
  实测挂死期间 `dmem.resp.valid` 全程为 0，1238 次 `mem.resp.valid` 全部伴随
  `imem.resp.valid`。
- 两次仲裁器修复尝试均失败（内存是同拍组合响应，寄存器化的在途标志会漏掉它），
  `arbiter.scala` 已逐字节恢复原状。
- 回归：dpath 修复对两配置无回归，32 项必需检查全过（含六项冒烟）。
- 证据：experiments/counter-baseline/results/mr3-diagnosis-20260912T031058Z
- 阶段 B 仍被单端口活锁阻塞。

## 2026-09-12 转向 1-stage：可配延迟内存接入与协议观测（claude）

用户指示改以 1-stage 为基础。理由不是 3-stage 太难，而是方案 §3.2 本就写明
单端口"会在 CPU 内提前合并 I/D…不适合作为本实验的固定边界"；1-stage 正是 §3.1
的目标形状（独立 I/D、无仲裁器），且 retire 本就门控 stall、用 reg_dmiss + 断言
强制"数据访存在途不取指"。3-stage 上诊断的两个故障在 1-stage 上都不存在。

- 计数方法第三次独立验证：R1 的 13 项在 1-stage 上与两个 3-stage 配置结果完全一致。
- 新增 `SodorMemLatencyAdapter` + `SodorMemProtocolMonitor`（`sodor/common/mem_latency.scala`），
  插在 core_port 与 SodorRequestRouter 之间，每个 I/D 口各一个。
- 延迟改为 CDE 参数 `SodorCoreParams.memLatency`，每个延迟一个独立 Config。
  起初用系统属性，make 不重新 elaborate，**五个延迟点的二进制完全相同**（指纹发现），
  差点得出每点都是延迟 0 的自证扫描。
- 结果：instret 在 0/1/2/4/8 全部精确正确，冒烟 3/3。周期两条关系四点精确成立：
  无访存 `cycles = N × (latency + 2)`，每次 load 额外 `latency + 1`。
  取指与访存完全串行、每口单 outstanding，是阶段 D 的量化基线。
- 协议观测：原生 I 口不是真正的 ready/valid 握手。一次运行 31022 次违规
  （rule1 31006 / rule2 16）而程序结果正确；核在 req 未 fire 时推进取指地址，
  停顿判据 `imiss` 只看 resp.valid 不看 req.ready。
  含义：接目标协议必须改核的取指逻辑，不是插适配器就够。
- 证据：experiments/counter-baseline/results/s1-latency-20260912T085159Z

## 2026-09-12（续）1-stage 取指/数据口改为真正的 ready/valid 握手（claude）

- 取指（`s1-01-fetch-handshake.patch`，dpath）：原来指令组合取自 resp 总线、
  req.ready 不参与控制。改为两段式，且 `fetch_resp` 只承认属于已 fire 请求的响应；
  保留同拍分支以免砍半 latency-0 吞吐。
- 数据口（`s1-02-data-handshake.patch`，cpath，4 行）：原来 valid 从发出举到响应，
  对已接受的请求重复举牌；加 `dreq_inflight` 跟踪已接受。
- 协议违规 **31022 → 8 → 0**。阴性对照三条：监视器字符串在二进制里、
  同次运行有 126096 行其他 trace、同一监视器在未改造核上触发 31022 次。
- 五个延迟点 instret 全对（每档 8 项）、冒烟 3/3、周期与改造前**逐位相同**
  （513/1539/2052/3078/5130）。握手合规零周期代价，方案 §6 担心的周期结构变化未发生。
- 下一步：把 resp 扩成 Decoupled 才能检查响应侧规则 3/5/6/7 与单 outstanding 计数。
- 证据：experiments/counter-baseline/results/s1-latency-20260912T085159Z

## 2026-09-12（续二）MemPortIo.resp 由 Valid 扩为 Decoupled（claude）

方案 §4.7 记的那个缺口。规则 3/5/6/7 在 ValidIO 上无法表述；
消费不了响应的一方只能丢弃，3-stage 活锁即源于此。

- 补丁：`s1-03-resp-decoupled`（+66/-12，含 memory/master_adapter/scratchpad_adapter/
  2·3·5·ucode core/3-stage arbiter）、`s1-04-latency-plumbing`（+92/-11）、
  新文件 `mem_latency.scala`（205 行：延迟适配器 + 协议监视器 + 故障注入）。
  其余核一律 `resp.ready := true.B` 保持等价。
- 三个坑：(a) `Input(new MemPortIo(...))` 不翻转 Flipped 里的 ready，导致
  监视器的 resp.fire 塌缩为 resp.valid、**rule 5 永远不可能触发**；改逐字段显式声明。
  靠查生成 SV 端口表发现，不是读代码发现的。(b) 无接收方的 ready 会被 DCE 整条删掉。
  (c) 其余核不驱动就是 DontCare（仿真为 X）。
- 阳性对照：新增 `memFaultMode`，`Sodor1StageFaultConfig` 每 2048 拍注入一次未请求的响应，
  监视器报 136 条（rule3×93、rule5×14、rule2×29），首条正在注入点 cyc=1023。
  **rule 7 至今无阳性对照，仍属未验证。**
- 结果：1-stage 五个延迟点 instret 全对、违规 0、周期与改造前逐位相同；
  3-stage 两配置 R1 回归全对、冒烟 3/3。
- 未覆盖：rule 4/6/8 未检查；后端仍忽略 ready（协议只施加在 CPU 边界）；
  随机延迟未做；2/5-stage 与 ucode 只到"能构建、行为不变"。
- 证据：experiments/counter-baseline/results/s1-latency-20260912T085159Z

## 2026-09-12（续三）rule 4 检查、合规后端、六条规则全部阳性对照（claude）

- 加 rule 4 检查后，latency=4 正常配置报 659 条违规，**全在后端侧**（核侧 0）：
  原生 `AsyncScratchPadMemory` 的 `resp.valid := req.valid` 在接受请求同拍应答。
  判据带 `outstanding === 0` 限定，因为方案允许旧响应与新请求同边沿握手。
- 新增 `SodorConformantBackend`（配置开关 `memConformantBackend`，默认关）：
  响应寄存一拍、保持到握手、`!busy` 才接受。lat=0/1/4 三档 instret 全对、
  六条规则全活下违规 0、冒烟 3/3。
- 代价量化：lat=0 周期 513 → 1026。两条关系现在在整个合规家族精确成立
  （含 latency 0）：`cycles = N × (latency+2)`、每次 load 额外 `latency+1`。
  改造前 lat=0 的 `N × 1` 是唯一异常点，因为组合读是另一个协议。
- 六条规则全部有阳性对照：rule1=31006（未改造核）、rule2=13918、rule3=93、
  rule4=659（原生后端）、rule5=14、rule7=3649。
- rule 7 花了五次才触达，过程本身有结论：faultMode 4 未加延迟时**不触发是正确的**，
  因为那是规则 4 允许的同边沿交接 —— 反向验证了判据。途中一处 `str.replace`
  锚点不符静默失效（查生成 SV 才发现），此后该类改动均带 assert。
- 3-stage 两配置回归不变、冒烟 3/3。
- 未覆盖：rule 6/8；随机延迟；2/5-stage 与 ucode 未接协议；
  合规后端只包 scratchpad，master 通路仍原生；3-stage 单端口活锁仍未修。
- 证据：experiments/counter-baseline/results/s1-latency-20260912T085159Z

## 2026-09-12（续四）3-stage 单端口 MMIO 活锁：用协议监视器定位并修复（claude）

之前手工改这个仲裁器失败两版。这次先把协议监视器接到 Stage3 tile（只读），
测量到底再动手。

- 协议签名：挂死时 `s3coreD rule2` 38800 次（每 2 拍一次），数据口反复举牌又撤回、
  从未被接受；同配置正常运行只有 922 条。
- 第一个假设（相位错配）被自己的测量推翻：38800 条**全部**是
  `ready_now=0 ready_prev=0`，`dmem.req.ready` 恒为 0，不是错相 ——
  所以"保持请求"这个修法无效。
- 根因（测得，稳态最后 20000 拍一致）：`dresp=1 memready=1 iv=0 mv=0`。
  `d_resp` 卡在 1 使 `dmem.req.ready := false` 恒成立，而共享端口一直 ready。
  `d_resp` 只在 `io.mem.req.fire` 清零，但 master 仲裁器上取指由 scratchpad 服务、
  `imem.req.valid` 恒 0，故永不 fire。**d_resp 在等一个永不到来的请求。**
  一次 MMIO 访问后该通路永久死亡：NMMIO=1 过、>=2 必挂。
- 修复一处（`s3-01-arbiter-turn-passing.patch`，+39/-4，逻辑仅一行）：
  `when (io.mem.req.fire || io.mem.resp.valid) { d_resp := false.B }`。
  响应路由在同拍由 d_resp 组合决定，寄存器更新下一拍生效，故该拍响应仍正确送达。
- 结果：单端口 mmio N=2/4/8 精确给出 5/7/11（原全部超时），R1 回归全对(8)、冒烟 3/3；
  双端口与 1-stage 不变且 mr3/mr6 完成。
- **mr3 是第三个独立故障且不在仲裁器里**：scratchpad 仲裁器稳态是正确交替
  （`dv=1 dr=1` fire → 置位；下一拍取指 fire → 清零，iresp/mresp 均在流动）。
  `s3coreI rule7` 38669 说明取指在途数无界增长 —— 下一步查 frontend，不是仲裁器。
- 独立发现：**3-stage 取指口本来就不是单 outstanding**（正常运行也有 876 次 rule7，
  frontend 流水取指）。方案规则 7 的"每口单 outstanding"基线对它不成立。
- 诊断打印保留但默认关闭（`-Dsodor.arbdiag=1`）。
- 证据：experiments/counter-baseline/results/s3-arbiter-20260912T182704Z

## 2026-09-12（续五）mr3 活锁：frontend 前进条件要求反相事件同拍（claude）

- 逐拍观测：挂死稳态两态交替，`rr` 与 `cpuready` 恒反相（内禀于单端口 ready 互补），
  frontend 的 `cpuready && rr && responded` 永不满足，同一 PC 反复投递。
- 先试去振荡项（dpath:125）无效，已回退。修复在 frontend（`s3-02`）：
  在 `req.fire` 时前进；`!inflight || resp.valid` 时才发下一个取指。
- 两个中间版本的错：门控 `if_pc_responsed` 复位死锁（第一条取指发不出）；
  门控只用 `!inflight` 取指串行、双端口 702→1089。放宽为 `|| resp.valid` 后修复。
- 结果：单端口 mr3/mr6 通（原超时），两配置 R1/mmio/冒烟全通；
  周期 702→639（双）、702/830→639/767（单），每次跳转省 1 拍，严格改善。
- **更正**：我曾报"双端口 513→639 退化 25%"，513 是 1-stage 的数，混入了 3-stage 注释；
  3-stage 双端口旧基线实测 702。
- 阶段 B 的三个阻塞故障（响应丢失 / MMIO d_resp / frontend 反相）均已修复，
  结构相同：必须同拍的事件由独立机制产生且恒差一拍。
- coreI rule7 仍非零（redirect 路径），取指口未严格单 outstanding；1-stage 不受 frontend 影响。
- 证据：experiments/counter-baseline/results/s3-arbiter-20260912T182704Z

## 2026-09-12（续六）计数任务阶段 B：最小性能基线矩阵（claude，待 Codex 验收）

- `bench/bench.S` 四个 body 各恰好 8 条/迭代，四类基准动态指令数相同（5+8·ITERS）；
  LOADUSE 与 LOADSEQ 指令相同仅顺序不同。一次运行回传 `(cycles<<16)|instret`，哨兵独立。
- 3 配置 × 4 基准 × 2 规模 × 2 重复 = 48 次全 ok；checker 从原始值重算、确定性、
  线性增长、跨配置 instret 一致全部通过；负向测试 6 项全部拒绝。
- 每迭代周期：ALU 10/10（两配置相同）；LOADUSE 13/16；LOADSEQ 10/14；STORESEQ 10/14。
  双端口下连续访存与 ALU 同价；load-use hazard 双端口 +1/对、单端口 +2/对。1-stage CPI 恰 1.000。
- 标签：原生三级整体比较＋计数补丁＋三处活锁修复＋resp Decoupled，不归因单一因素。
- 证据：/home/engineer/fpga/experiments/counter-baseline/results/phaseB-20260912T223812Z；入口见 `B-README.md`。

## 2026-09-13 Codex 验收退回的验证链修补（claude，待 Codex 复核）

- 四个漏洞全部修补并有修补前/后对照：ROI witness per-PC（6/7）、严格退出判定（只认 255 且双签名一致）、
  B 身份一致性、监视器 req_data。Codex 对抗脚本 3 洞 → 0；归档结果原样通过。
- 负向集合扩展到 Codex 列出的每一项（r1-negative2 / b-negative2 / rtl-data-hold-check）。
- RTL data-only：Fault5 1272、Fault6 636、Fault7 合法对照 0，addr_changed 全 0。前两版零触发原因：
  后端口从不等待（适配器延迟遮住慢 ready），改 7 拍窗口。
- **新发现**：3-stage 单端口 master 仲裁器 `mem.req.bits.data := dmem.req.bits.data` 无条件直连，
  取指等待时数据字段变化，rule1 违规 5177 次；功能无害，未修（超出授权），交 Codex 决定。
- 重采集用当前树重建模拟器：R1 30 条测量值零差异，B 48 行逐值相同；两个失效目录标 INVALID 保留。
- 自己的错：Aborting 误判、rework 命名不匹配。
- 报告：experiments/counter-baseline/CLAUDE_POST_R1_REWORK.md；R1 /home/engineer/fpga/experiments/counter-baseline/results/r1-rework-20260913T001808Z；B /home/engineer/fpga/experiments/counter-baseline/results/phaseB-rework-20260913T001850Z

## 2026-09-13（续）rework2：仲裁器数据字段 + RTL 门禁（claude，待 Codex 复核）

- 数据字段跟随已选请求：5177 → 2；残留 2 次与 4 次总线重选周期重合。ARBDIAG 证实：内存变 ready 同拍数据请求劫持等待中的取指（选源依赖 fire）。
- 实验 #1 总线锁死锁；实验 #2 按 valid 选源可行（违规 0/0、B 单端口周期逐值相同），均未入工作树，交裁定。
- RTL runner：独立目录、真实退出码、双签名、结果值、覆盖事件；Fault7 加合法 fire 后改数据；负向 4 项（含 Codex 的 timeout 函数替身）。
- --rebuild 唯一目录；--results；总入口含全部负向与 RTL，本轮退出 0。
- R1/B 在重建 sim 上通过且与上一轮零差异。报告 experiments/counter-baseline/CLAUDE_REWORK2.md。

## 2026-09-13（续）rw3：仲裁器请求承诺、独立 RTL 测试、legacy/strict 边界（claude，待 Codex 复核）

- 独立仲裁器 TB（Chisel + ChiselStage + Verilator，逐笔 scoreboard + 三监视器）：legacy 在竞争/背压/流水化下违反共享口契约或事务失败，strict 全过；非法源在 strict 下 assert、在 legacy 边界下计数且撤回的 store 零执行。
- strict 仲裁器：按 valid 选源（不看 imem.valid，避免与核的组合环）、锁定到 fire、按序归属队列与轮转分离。
- legacy 边界最终为"直通撤回 + 计数"：立即接受版会执行核在 RAW 停顿期发出的未验证地址读（fcn 一位，M_X==M_XRD，TileLink 非法地址断言）——实证 Codex 的"不能执行被取消的访问"。根治提案 core-01。
- router 改双侧在途计数（原按最后地址路由，strict 记账下死锁）；master 响应保持（原脉冲丢响应）。
- coreI rule7 判定：是我 s3-02 的同拍记账 bug（core-03 提案归零）；coreD rule2 是核真实违约（core-01）。
- strict SoC 需 core-03 才能运行；core-03 未入树，交裁定。应用后 strict 与 legacy 单端口周期逐值相同、rule1/3/4/5/7 为零。
- 自己的错：pkill -f 自杀三次、make 假成功（已加 sha 校验）、诊断 opt-in 忘带。报告 CLAUDE_RW3.md。
- 交付态回归（rw3-final2）：R1/B 与 rework2 零差异；legacy 单端口协议计数不变；strict(+core-03) 周期与 legacy 逐值相同、rule1/3/4/5/7=0。
- 交付态首轮曾暴露：无门控的响应保持让 s3-02 幽灵响应被 legacy d_resp 投给下一次数据请求，MMIO 读到错误数据（19 vs 122）；已将保持随 arbiterStrict 门控，并在回归中加入 MMIO 数据对照（instret 对错误数据是盲的）。

## 2026-09-13（续）rw4：core-03 入树、冗余机制回退、TB 收口（claude，待 Codex 复核）

- core-03 入树（互斥 when/.elsewhen + 断言 + debug 导出）；latency-0 组合存储器与 frontend 门控成环（firtool），前提定为寄存响应。
- router 计数路由与 master 响应保持均判定为冗余并回退，各加单在途/必须接收断言；交付态 R1/B 与 rework2 零差异，legacy 单端口 coreI rule7 217→0、mastArb rule1 12→0，strict 与 legacy 周期逐值相同，MMIO 数据 122 vs 121。
- TB v8：流水化有序后端+真实存储+读回、双在途源、LFSR 背压、归属队列覆盖；runner v3 全规则门控与精确期望。首轮多在途失败为源模型同拍期望队列顺序 bug（Codex 发现 3），已修。
- 自己的错：一个 heredoc 写在未触发的 if 里导致作业启动了不存在的脚本；MMIO 参考值因 r() 定义顺序为空。报告 CLAUDE_RW4.md。

## 2026-09-14 Claude：RW6 HoldD 验证补充 + RW9 定时器中断根因/修复（待 Codex 审）
- 入口：`experiments/counter-baseline/CLAUDE_RW6.md`（§0 时间线；§2–§7 HoldD 冒烟/回归/R1/B/延迟定向/等价；§9 Codex RW7/RW8 状态；§10 中断根因与 `recordInterrupt` 修复）。提案 `.coord/proposals/claude-rw6-acceptance.md`。
- 结论：HoldD D 口 rule1/2 归零且周期逐值不变；定时器中断失败根因是核未向 CSR 报告中断（上游缺陷），独立开关修复后 HoldDMMIOIrq / HoldIDMMIOIrq 定时器测试 PASS。原生配置 SV 逐文件不变。

## 2026-09-14 Codex：RW11 已验收

- 任务书：`.coord/proposals/codex-rw11-latency-matrix.md`。固定 HoldIDMMIOIrq 单端口核心，扫描 D 路径接受等待与响应延迟 3×3 矩阵；先审计参数时序，再验证 adapter TB 和性能采集。
- Claude 已交付 9 配置 144 行及参考 16 行、30 smoke、adapter TB 与最慢点中断测试。独立复核原始 CSV checker 通过，但整组互换模拟器 SHA、错 A、错 raw_tohost、smoke 协议事件、参考 timeout 五个反例均漏检，故尚不最终验收。
- 补修任务 `.coord/proposals/codex-rw11-validation-rework.md` 已交 Claude，要求绑定 manifest/原始字段、强制双退出签名并传播中断子任务失败；旧结果保留。独立脚本 `scripts/codex-rw11-review.py` 及结果 `results/codex-rw11-review-za53zq3a/` 记录抽跑和反例。队列/多在途、I 路径延迟及真实 FPGA 后端另立任务。
- Codex 独立抽跑完成：A0R0/A8R0/A0R8/A8R8 × LOADUSE32/64 共 8 次与归档编码结果一致，双签名、协议检查通过，模拟器/ELF SHA 符合 manifest/CSV；归档 A8R8-strict 和 A2R2-lfsr TB 重跑通过。本轮使用已有二进制，未重新构建 RTL。
- v2 独立复核：完整重跑与旧日志重核验各 160+30+3，R 补点 96+18，全部通过 `--logs --files`，原五反例均正确拒绝。证据 `results/codex-rw11-v2-tom0o0w3/`，独立脚本 `scripts/codex-rw11-v2-review.py`。原始档未修改。
- 仍未最终验收：参考 repeat=1 全部 timeout、smoke expected 与结果同时改成999、空 IRQ 日志（含 --logs）三个反例都错误返回0。已分派 `.coord/proposals/codex-rw11-v2-final-gates.md`，只补验证链；性能数据限定认可，整体验收待三门禁收口。
- 最终验收：以上三项已修复。独立结果 `results/codex-rw11-v2-ed6hkm1i/`：full/reverified/rsweep 全通过 logs/files；八反例均返回1且为目标原因，无解析崩溃。空IRQ现明确拒绝 no_pass_marker，参考repeat1与smoke期望同改被拒。Claude负向36/36归档已审，本轮独立重放其中八个反例，未声称重跑全部36项。
- 新旧档核验入口为 `rw11-matrix-reverified-20260914T135256Z`，通过 manifest 明示历史退出码来源；旧064317Z结果仍保留、不再作为当前门禁通过证据。源码相关写入权已由Claude交回Codex。
- Claude 获本任务相关源码与测试写入权；EXECUTION 和总方案仍由 Codex 维护。交回后 Codex 独立抽跑验收。

## 2026-09-14 Claude：RW10 中断交错覆盖（Codex 已验收）
- 入口 `experiments/counter-baseline/CLAUDE_RW10.md`；runner `scripts/rw10-irq-run.sh`。Codex 独立复核归档日志：Accept8 配置下 timer2/timer4/MSIP/MEIP 均有 pending=1 DEFER，所有镜像内 TAKE 均恰一次且 pending/dmem/wbwait=0、cause 正确；HoldD/HoldID 程序级 12 项 PASS；未修配置负向五项 code87，timer5 触发 HoldD "accepted without free WB slot" 断言（原生中断 kill 与 fire 同拍）。原生 SV 318/0。边界：HoldID 未取逐拍 diag，中断+异常/eret/嵌套未覆盖，MEIP 仅 UART 源。
