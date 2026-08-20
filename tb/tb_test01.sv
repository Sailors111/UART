`timescale 1ns/1ps

// Test 01: 32-bit AXI-Stream到8-bit UART的TKEEP/TLAST及输出反压测试。
// 发送三个AXIS beat：
//   beat0: TKEEP=4'b1111, TLAST=0
//   beat1: TKEEP=4'b0111, TLAST=0
//   beat2: TKEEP=4'b0011, TLAST=1
//
// UART按低字节优先发送有效lane，因此实际发送9个字节：
//   11 22 33 44 55 66 77 99 aa
// 接收端按4字节重新组装，并在TREADY拉低期间检查输出保持稳定。
// UART线只传输字节，输入TLAST不透明传输；最后一个输出TLAST由接收超时产生。
// 预期收到：
//   44332211, TKEEP=1111, TLAST=0
//   99776655, TKEEP=1111, TLAST=0
//   000000aa, TKEEP=0001, TLAST=1
module tb_test01;

    localparam integer AXIS_DATA_WIDTH    = 32;
    localparam integer UART_DATA_WIDTH    = 8;
    localparam integer AXIS_KEEP_WIDTH    = 4;
    localparam integer UART_CLK_FREQ_HZ   = 80_000_000;
    localparam integer BAUD_RATE          = 5_000_000;
    localparam integer OVERSAMPLE         = 16;
    localparam integer RX_TIMEOUT_CYCLES  = 512;

    reg axis_clock;
    reg uart_clock;
    reg reset;
    wire rst_n = ~reset;

    wire tx_0;
    wire tx_1;
    wire rx_0 = tx_1;
    wire rx_1 = tx_0;

    reg                         s_axis_tvalid_0;
    wire                        s_axis_tready_0;
    reg  [AXIS_DATA_WIDTH-1:0] s_axis_tdata_0;
    reg  [AXIS_KEEP_WIDTH-1:0] s_axis_tkeep_0;
    reg                         s_axis_tlast_0;

    wire                        m_axis_tvalid_0;
    reg                         m_axis_tready_0;
    wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata_0;
    wire [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep_0;
    wire                        m_axis_tlast_0;


    reg                         s_axis_tvalid_1;
    wire                        s_axis_tready_1;
    reg  [AXIS_DATA_WIDTH-1:0] s_axis_tdata_1;
    reg  [AXIS_KEEP_WIDTH-1:0] s_axis_tkeep_1;
    reg                         s_axis_tlast_1;

    wire                        m_axis_tvalid_1;
    reg                         m_axis_tready_1;
    wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata_1;
    wire [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep_1;
    wire                        m_axis_tlast_1;


    reg [31:0] recv_data;
    reg [3:0]  recv_keep;
    reg        recv_last;

    always #5    axis_clock = ~axis_clock;
    always #6.25 uart_clock = ~uart_clock;

    // 导出完整测试平台层次，便于在GTKWave中观察AXI-Stream和UART波形。
    // 重点信号包括s_axis_tdata/tkeep/tlast和m_axis_tdata/tkeep/tlast。
    initial begin
        $dumpfile("wave/tb_test01.vcd");
        $dumpvars(0, tb_test01);
    end

    task automatic send_beat;
        input [31:0] data;
        input [3:0]  keep;
        input        last;
        integer wait_cycles;
        begin
            // 在上升沿后的NBA阶段更新激励，避免与DUT在Active区竞争。
            @(posedge axis_clock);
            s_axis_tdata_0  <= data;
            s_axis_tkeep_0  <= keep;
            s_axis_tlast_0  <= last;
            s_axis_tvalid_0 <= 1'b1;

            wait_cycles = 0;
            while (1) begin
                @(posedge axis_clock);
                if (s_axis_tready_0 === 1'b1) begin
                    // 本上升沿完成握手，在NBA阶段撤销输入。
                    s_axis_tvalid_0 <= 1'b0;
                    s_axis_tdata_0  <= 32'd0;
                    s_axis_tkeep_0  <= 4'd0;
                    s_axis_tlast_0  <= 1'b0;
                    disable send_beat;
                end

                wait_cycles = wait_cycles + 1;
                if (wait_cycles >= 10000)
                    $fatal(1, "send beat timeout waiting for s_axis_tready");
            end
        end
    endtask

    task automatic recv_beat_with_backpressure;
        output [31:0] data;
        output [3:0]  keep;
        output        last;
        input integer stall_cycles;
        integer wait_cycles;
        integer stall_index;
        begin
            // TREADY保持为0，先等待接收端给出有效数据。
            wait_cycles = 0;
            while (m_axis_tvalid_1 !== 1'b1) begin
                @(posedge axis_clock);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles >= 100000)
                    $fatal(1, "receive beat timeout waiting for m_axis_tvalid");
            end

            data = m_axis_tdata_1;
            keep = m_axis_tkeep_1;
            last = m_axis_tlast_1;

            // 主动施加反压，检查TVALID及payload在等待期间保持稳定。
            for (stall_index = 0; stall_index < stall_cycles; stall_index = stall_index + 1) begin
                @(posedge axis_clock);
                if (m_axis_tvalid_1 !== 1'b1)
                    $fatal(1, "m_axis_tvalid dropped during backpressure");
                if (m_axis_tdata_1 !== data)
                    $fatal(1, "m_axis_tdata changed during backpressure");
                if (m_axis_tkeep_1 !== keep)
                    $fatal(1, "m_axis_tkeep changed during backpressure");
                if (m_axis_tlast_1 !== last)
                    $fatal(1, "m_axis_tlast changed during backpressure");
            end

            // 拉高TREADY后，等待下一个上升沿完成握手。
            @(posedge axis_clock);
            m_axis_tready_1 <= 1'b1;
            @(posedge axis_clock);
            if (m_axis_tvalid_1 !== 1'b1)
                $fatal(1, "m_axis_tvalid missing on handshake cycle");
            m_axis_tready_1 <= 1'b0;

            // 再等一个上升沿，让DUT完成握手后的寄存器更新。
            @(posedge axis_clock);
            if (m_axis_tvalid_1 !== 1'b0)
                $fatal(1, "m_axis_tvalid did not clear after handshake");
        end
    endtask

    task automatic check_beat;
        input integer index;
        input [31:0] expected_data;
        input [3:0]  expected_keep;
        input        expected_last;
        input integer stall_cycles;
        begin
            recv_beat_with_backpressure(
                recv_data, recv_keep, recv_last, stall_cycles
            );

            if (recv_data !== expected_data)
                $fatal(1, "beat%0d data mismatch: expected %08x, got %08x",
                    index, expected_data, recv_data);
            if (recv_keep !== expected_keep)
                $fatal(1, "beat%0d keep mismatch: expected %b, got %b",
                    index, expected_keep, recv_keep);
            if (recv_last !== expected_last)
                $fatal(1, "beat%0d last mismatch: expected %b, got %b",
                    index, expected_last, recv_last);

            $display("PASS beat%0d: data=%08x keep=%b last=%b",
                index, recv_data, recv_keep, recv_last);
        end
    endtask

    axis_top #(
        .UART_CLK_FREQ_HZ  (UART_CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .OVERSAMPLE        (OVERSAMPLE),
        .AXIS_DATA_WIDTH   (AXIS_DATA_WIDTH),
        .UART_DATA_WIDTH   (UART_DATA_WIDTH),
        .AXIS_KEEP_WIDTH   (AXIS_KEEP_WIDTH),
        .TX_FIFO_DEPTH     (16),
        .RX_FIFO_DEPTH     (16),
        .RX_PACKET_LEN     (16),
        .RX_TIMEOUT_CYCLES (RX_TIMEOUT_CYCLES)
    ) dut0 (
        .axis_clk       (axis_clock),
        .uart_clk       (uart_clock),
        .rst_n          (rst_n),
        .rx             (rx_0),
        .tx             (tx_0),
        .s_axis_tvalid  (s_axis_tvalid_0),
        .s_axis_tready  (s_axis_tready_0),
        .s_axis_tdata   (s_axis_tdata_0),
        .s_axis_tkeep   (s_axis_tkeep_0),
        .s_axis_tlast   (s_axis_tlast_0),
        .m_axis_tvalid  (m_axis_tvalid_0),
        .m_axis_tready  (m_axis_tready_0),
        .m_axis_tdata   (m_axis_tdata_0),
        .m_axis_tkeep   (m_axis_tkeep_0),
        .m_axis_tlast   (m_axis_tlast_0)
    );

    axis_top #(
        .UART_CLK_FREQ_HZ  (UART_CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .OVERSAMPLE        (OVERSAMPLE),
        .AXIS_DATA_WIDTH   (AXIS_DATA_WIDTH),
        .UART_DATA_WIDTH   (UART_DATA_WIDTH),
        .AXIS_KEEP_WIDTH   (AXIS_KEEP_WIDTH),
        .TX_FIFO_DEPTH     (16),
        .RX_FIFO_DEPTH     (16),
        .RX_PACKET_LEN     (16),
        .RX_TIMEOUT_CYCLES (RX_TIMEOUT_CYCLES)
    ) dut1 (
        .axis_clk       (axis_clock),
        .uart_clk       (uart_clock),
        .rst_n          (rst_n),
        .rx             (rx_1),
        .tx             (tx_1),
        .s_axis_tvalid  (s_axis_tvalid_1),
        .s_axis_tready  (s_axis_tready_1),
        .s_axis_tdata   (s_axis_tdata_1),
        .s_axis_tkeep   (s_axis_tkeep_1),
        .s_axis_tlast   (s_axis_tlast_1),
        .m_axis_tvalid  (m_axis_tvalid_1),
        .m_axis_tready  (m_axis_tready_1),
        .m_axis_tdata   (m_axis_tdata_1),
        .m_axis_tkeep   (m_axis_tkeep_1),
        .m_axis_tlast   (m_axis_tlast_1)
    );

    initial begin
        axis_clock = 1'b0;
        uart_clock = 1'b0;
        reset      = 1'b1;

        s_axis_tvalid_0 = 1'b0;
        s_axis_tdata_0  = 32'd0;
        s_axis_tkeep_0  = 4'd0;
        s_axis_tlast_0  = 1'b0;
        m_axis_tready_0 = 1'b1;

        s_axis_tvalid_1 = 1'b0;
        s_axis_tdata_1  = 32'd0;
        s_axis_tkeep_1  = 4'd0;
        s_axis_tlast_1  = 1'b0;
        m_axis_tready_1 = 1'b0;

        repeat (20) @(posedge axis_clock);
        reset <= 1'b0;
        repeat (5) @(posedge axis_clock);

        send_beat(32'h44332211, 4'b1111, 1'b0);
        send_beat(32'h88776655, 4'b0111, 1'b0);
        send_beat(32'h0000aa99, 4'b0011, 1'b1);

        check_beat(0, 32'h44332211, 4'b1111, 1'b0, 5);
        check_beat(1, 32'h99776655, 4'b1111, 1'b0, 3);
        check_beat(2, 32'h000000aa, 4'b0001, 1'b1, 7);

        $display("TEST01 PASS: TKEEP/TLAST and output backpressure");
        $finish;
    end

    initial begin
        #200_000;
        $fatal(1, "test01 timeout");
    end

endmodule
