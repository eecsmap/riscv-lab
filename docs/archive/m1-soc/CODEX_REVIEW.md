# M1 SoC集成验收（2026-09-15）

结论：通过，本轮限定为无CPU旧SoC功能仿真；不等于板级DDR或CPU/xv6完成。

## 独立验证

直接运行交付二进制，未重新编译。证据 `codex-review-Bbrjk1/`。

- basic：退出0，6135周期，768笔、错误0。
- backpressure：退出0，8889周期，768笔、错误0；CPU响应背压1157拍、TL A等待243拍。
- fault-payload：退出1，6627周期，84个数据错误；首个错误与交付一致，非超时冒充故障成功。
- 三例AXI均AR=R=315、AW=W=B=443，读写均非零、结束计数闭合。源码及生成RTL确认connectSimAXIMem使用AXI4RAM，教学master经sbus进入实际内存口，无桥旁TLRAM替代。
- basic以max-cycles=200独立运行返回2（SOCTB TIMEOUT），日志 `/tmp/codex-m1soc-timeout.log`。
- 三例源码、RTL、二进制哈希核验均通过；源码清单在实际teaching目录核验。
- 修改后M1-b单元13例独立重跑，5正向退出0，8反例退出134并命中各自目标理由；见unit-*.log和unit-exits.txt。首次临时执行命令在echo中先做basename导致退出码打印失真，已用立即保存case_rc的第二轮复跑纠正；以持久目录第二轮为准。

## 范围与观察

零tile配置保留外设，使用PLIC/CLINT/debug替身sink及resetVectorBits覆盖，均仅在独立测试配置内。不宣称中断消费、HTIF/DMA并发、启动或热复位已测。

7笔本地拒绝与2笔真实error访问通过；SoC无法构造的unsupported-size保留单元覆盖。covReadback=317包含1笔未比较内容的BootROM合法读与1笔error读，真正DRAM数据读回315笔（15笔定向+300笔随机），不能将317都称为数据比对。

非阻断维护项：runner当前检查AXI计数下限，未自动门禁AR=R、AW=W=B；本轮由Codex逐例人工核验闭合。tools.txt为空（工具环境加载前查询版本且忽略失败），后续应将版本采集放到环境加载后。二者不改变本轮实际运行结果，未来批量实验前宜补齐。

后续应细化M2最简执行核规格和裸机验证任务；本轮不授权上板，也未分派M2实现。
