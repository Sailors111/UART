# AXI-Stream UART Learning Project

这是一个用于学习 AXI-Stream、异步 FIFO 和 UART 的小型 RTL 项目。

## 数据路径

```text
AXI-Stream slave
        |
        v
axis_tx (32-bit beat -> 8-bit bytes)
        |
        v
TX async_fifo (axis_clk -> uart_clk)
        |
        v
uart_tx -> serial line -> uart_rx
                            |
                            v
RX async_fifo (uart_clk -> axis_clk)
                            |
                            v
axis_rx (8-bit bytes -> 32-bit beat)
                            |
                            v
                    AXI-Stream master
```

波特率由 `axis_top.BAUD_RATE` 编译期参数设置。项目不包含运行时配置寄存器或 AXI-Lite。

AXI-Stream 数据接口包含 `TDATA/TKEEP/TLAST/TVALID/TREADY`。UART 线上只传输字节，
输入侧 `TLAST` 不会透明传到接收端；`axis_rx` 根据 `RX_PACKET_LEN` 或
`RX_TIMEOUT_CYCLES` 重新产生输出 `TLAST`。

## RTL

- `axis_top.v`: 顶层和完整数据路径。
- `axis_tx.v`: 根据 `TKEEP` 将 AXI beat 拆成 UART 字节。
- `axis_rx.v`: 将 UART 字节组装为 AXI beat，并产生 `TKEEP/TLAST`。
- `async_fifo.v`: 使用 Gray 指针跨越 AXI 和 UART 时钟域。
- `baud_gen.v`: 产生 UART 发送 tick 和接收过采样 tick。
- `uart_tx.v`: UART 发送状态机。
- `uart_rx.v`: 两级同步、16 倍过采样和 UART 接收状态机。

## Tests

- `tb_test00`: 两个 DUT 的单字节双向回环，dut0 发送 `0x55`，dut1 检查后回传。
- `tb_test01`: 多 beat、不同 `TKEEP`、接收超时产生 `TLAST` 和输出反压。
- `tb_test02`: 深度为 4 的异步 FIFO 极端时钟比、满空边界和多次指针绕回。

运行全部测试：

`xmake build -a` 先使用 Icarus Verilog 编译全部测试，然后分别运行：

```bash
xmake build -a

xmake run tb_test00
xmake run tb_test01
xmake run tb_test02
```

也可以按照 `docs/run.txt` 中的命令直接使用 Icarus Verilog。
