// rtl/axis_rx.v
// AXI-Stream宽度转换：将UART字节流组装成AXIS beat。
// 当前UART数据宽度限定为8位，低字节先进入AXIS数据。
// RX_PACKET_LEN的单位是AXIS beat数量，不是UART字节数量。

module axis_rx #(
    parameter integer AXIS_DATA_WIDTH   = 32,
    parameter integer UART_DATA_WIDTH   = 8,
    parameter integer AXIS_KEEP_WIDTH   = AXIS_DATA_WIDTH / 8,
    parameter integer RX_PACKET_LEN     = 16,
    parameter integer RX_TIMEOUT_CYCLES = 100_000
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         rx_rd_valid,
    output wire                         rx_rd_ready,
    input  wire [UART_DATA_WIDTH-1:0]   rx_rd_data,

    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0]   m_axis_tkeep,
    output wire                         m_axis_tlast
);

    localparam integer BYTE_INDEX_WIDTH =
        (AXIS_KEEP_WIDTH <= 1) ? 1 : $clog2(AXIS_KEEP_WIDTH);

    localparam integer PACKET_COUNT_WIDTH =
        (RX_PACKET_LEN <= 1) ? 1 : $clog2(RX_PACKET_LEN);

    localparam integer TIMEOUT_COUNT_WIDTH =
        (RX_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(RX_TIMEOUT_CYCLES);

    localparam [1:0] RX_COLLECT   = 2'd0;       // 收集UART字节，逐渐组装成一个AXI beat
    localparam [1:0] RX_WAIT_NEXT = 2'd1;       // 暂存一个AXI beat，如果超时则直接发送
    localparam [1:0] RX_OUTPUT    = 2'd2;       // 下游握手后直接输出一个AXI beat

    localparam [31:0] LAST_PACKET_BEAT_FULL = RX_PACKET_LEN - 1;
    localparam [PACKET_COUNT_WIDTH-1:0] LAST_PACKET_BEAT =
        LAST_PACKET_BEAT_FULL[PACKET_COUNT_WIDTH-1:0];

    localparam [31:0] LAST_TIMEOUT_COUNT_FULL = RX_TIMEOUT_CYCLES - 1;
    localparam [TIMEOUT_COUNT_WIDTH-1:0] LAST_TIMEOUT_COUNT =
        LAST_TIMEOUT_COUNT_FULL[TIMEOUT_COUNT_WIDTH-1:0];

    reg [1:0] rx_state;

    reg [AXIS_DATA_WIDTH-1:0]   data_reg;
    reg [AXIS_KEEP_WIDTH-1:0]   keep_reg;
    reg                         last_reg;
    reg                         valid_reg;

    reg [BYTE_INDEX_WIDTH-1:0]    byte_index;
    reg [PACKET_COUNT_WIDTH-1:0]  packet_beat_count;
    reg [TIMEOUT_COUNT_WIDTH-1:0] timeout_count;

    initial begin
        if (AXIS_DATA_WIDTH <= 0 || (AXIS_DATA_WIDTH % 8) != 0)
            $error("axis_rx AXIS_DATA_WIDTH must be a positive multiple of 8");

        if (UART_DATA_WIDTH != 8)
            $error("axis_rx currently supports UART_DATA_WIDTH=8 only");

        if (AXIS_KEEP_WIDTH != AXIS_DATA_WIDTH / 8)
            $error("axis_rx AXIS_KEEP_WIDTH does not match AXIS_DATA_WIDTH");

        if (RX_PACKET_LEN <= 0)
            $error("axis_rx RX_PACKET_LEN must be greater than 0");

        if (RX_TIMEOUT_CYCLES <= 0)
            $error("axis_rx RX_TIMEOUT_CYCLES must be greater than 0");
    end

    // 有待输出beat时停止读取FIFO，保证AXIS反压期间输出稳定。
    assign rx_rd_ready = (rx_state == RX_COLLECT);

    assign m_axis_tvalid = valid_reg;
    assign m_axis_tdata  = data_reg;
    assign m_axis_tkeep  = keep_reg;
    assign m_axis_tlast  = last_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state          <= RX_COLLECT;
            data_reg          <= {AXIS_DATA_WIDTH{1'b0}};
            keep_reg          <= {AXIS_KEEP_WIDTH{1'b0}};
            last_reg          <= 1'b0;
            valid_reg         <= 1'b0;
            byte_index        <= {BYTE_INDEX_WIDTH{1'b0}};
            packet_beat_count <= {PACKET_COUNT_WIDTH{1'b0}};
            timeout_count     <= {TIMEOUT_COUNT_WIDTH{1'b0}};
        end else begin
            case (rx_state)
                RX_COLLECT: begin
                    if (rx_rd_valid) begin
                        // rx_rd_ready在RX_COLLECT状态为1，这里完成一个字节握手。
                        data_reg[byte_index * UART_DATA_WIDTH +: UART_DATA_WIDTH] <= rx_rd_data;
                        keep_reg[byte_index] <= 1'b1;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};

                        if (byte_index == AXIS_KEEP_WIDTH - 1) begin
                            // 收满一个32位AXIS beat。
                            if (packet_beat_count == LAST_PACKET_BEAT) begin
                                // 达到RX_PACKET_LEN，当前beat就是包尾。
                                last_reg  <= 1'b1;
                                valid_reg <= 1'b1;
                                rx_state  <= RX_OUTPUT;
                            end else begin
                                // 先暂存完整beat，等待下一个字节或超时。
                                rx_state <= RX_WAIT_NEXT;
                            end

                            byte_index <= {BYTE_INDEX_WIDTH{1'b0}};
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end else if (|keep_reg) begin       // AXIS beat未满且非空
                        // 只对已经收到部分数据的当前包计时。
                        if (timeout_count == LAST_TIMEOUT_COUNT) begin
                            last_reg  <= 1'b1;
                            valid_reg <= 1'b1;
                            rx_state  <= RX_OUTPUT;
                            timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                        end else begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                    end else begin
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                    end
                end

                RX_WAIT_NEXT: begin
                    // 当前beat已满，但尚未确认是否是包尾。
                    if (rx_rd_valid) begin
                        // FIFO中已有下一个字节，当前beat不是包尾。
                        last_reg  <= 1'b0;
                        valid_reg <= 1'b1;
                        rx_state  <= RX_OUTPUT;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                    end else if (timeout_count == LAST_TIMEOUT_COUNT) begin
                        // 没有后续字节，当前完整beat作为超时结束的包尾。
                        last_reg  <= 1'b1;
                        valid_reg <= 1'b1;
                        rx_state  <= RX_OUTPUT;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                RX_OUTPUT: begin
                    if (m_axis_tready) begin
                        data_reg     <= {AXIS_DATA_WIDTH{1'b0}};
                        keep_reg     <= {AXIS_KEEP_WIDTH{1'b0}};
                        valid_reg    <= 1'b0;
                        byte_index   <= {BYTE_INDEX_WIDTH{1'b0}};
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};

                        if (last_reg) begin
                            // 一个包结束，下一个字节重新从新包开始计数。
                            last_reg          <= 1'b0;
                            packet_beat_count <= {PACKET_COUNT_WIDTH{1'b0}};
                        end else begin
                            packet_beat_count <= packet_beat_count + 1'b1;
                        end

                        rx_state <= RX_COLLECT;
                    end
                end

                default: begin
                    rx_state  <= RX_COLLECT;
                    valid_reg <= 1'b0;
                    last_reg  <= 1'b0;
                end
            endcase
        end
    end

endmodule
