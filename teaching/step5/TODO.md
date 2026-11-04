# 第 5 步的 TODO：四块

这一步不改 RTL。如果 TODO 1 不过，问题在前四步留下的东西里，`README.md` 的"失败了先看哪里"会指过去。

## TODO 1：跑通

```sh
make step4            # 先确认第 4 步全过
make step5            # 第一次约 20 秒 verilate，之后每个程序几秒
```

期望四行 `ok`，每行后面是程序打印的字。不过就看 FAIL 下面那段"核做了什么"，对照 README 的失败表。

## TODO 2：读启动链

打开 `out/step5/boot01_marker.log`，找出下面每一环发生在第几拍，填进表里。每一行后面给了一个找它的办法。

| 事件 | 第几拍 | 怎么找 |
| --- | --- | --- |
| 第一次取指，地址 0x10040 | | 第一行 `EV ... REQ` |
| 主机第一次往 DRAM 写（装程序） | | 第一行 `EVA ... AW addr=0x80000000` |
| 主机拉高 msip | | `IRQLEVEL msip=1` |
| 你的核接受中断（epc 是多少？为什么是它？） | | `TRAP interrupt=1` |
| msip 落下（ROM 处理程序清的） | | `IRQLEVEL msip=0` |
| `mret` 退休 | | `COMMIT pc=0x…10098` |
| 第一次从 0x8000_0000 取指 | | `REQ ... pc=0x0000000080000000` |
| 程序打印第一个字 | | 行首多出一个字母的那一行 |
| 主机看到退出码 | | `EVH ... HOSTDONE` |

再回答两个问题：

1. 主机装程序的那段时间里，你的核退休了多少条指令？它们都是哪几条？（数一数第一次 `AW addr=0x8…` 到 `msip=1`
   之间的 `COMMIT`）
2. `.check` 文件（`out/step5/boot01_marker.check`）里的 `note: boot chain:` 一行和你的表对得上吗？

## TODO 3：你的第一个系统程序

```sh
cp step5/hello.c work/hello.c
# 改 work/hello.c 里的字
make step5-run PROG=work/hello.c
```

然后加一点东西，任选：

- 打印你的名字和 `mhartid`；
- 用一个循环跑 1000 次 `x = x * 3 + 1`……等等，RV64I 没有乘法。改成 `x = (x << 1) + x + 1`，然后用 `mcycle`、`minstret`
  算出这个循环的 CPI；
- 打印 `misa`，解码出你的核声称自己支持哪些扩展。

`main` 返回非零，`make step5-run` 就报 FAIL，可以用它来做自检。

## TODO 4：追踪一个总线错误

打开 `out/step5/boot04_badaddr.log`，找到地址 `0x50000000` 的那个请求，往下看三行：

1. `REQ ... addr=0x50000000`：哪条指令发的？（`pc=` 是多少，在 `boot04_badaddr.S` 里是哪一行）
2. `RESP ... error=1`：隔了几拍回来？
3. `TRAP interrupt=0 cause=…05`：epc、tval 各是什么，为什么是它们？

然后在你的 `tcpu_core.v` 里找到把 `resp_error` 变成 cause 5 的那几行，写一句注释说明它是在哪一拍、哪个状态生效的。
最后回答：如果去掉那几行，boot04 会以什么方式失败？（答案在 README 的失败表里，自己先想。）
