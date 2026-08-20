
// rtl/uart_rx.v    UART接收模块：core接收外设的数据


module uart_rx #(
    parameter integer UART_DATA_WIDTH = 8,
    parameter integer OVERSAMPLE = 16
)(
    input  wire                  clk,         // 系统时钟
    input  wire                  rst_n,       // 低有效复位

    input  wire                  sample_tick,   

    input  wire                  rx,          // UART接收线

    input  wire                  rx_ready,    // 下游FIFO/模块可以接收
    output reg  [UART_DATA_WIDTH-1:0] rx_data,     // 接收到的数据
    output reg                   rx_valid,    // rx_data有效
    output reg                   frame_error  // stop bit错误脉冲
);

    localparam integer SAMPLE_CNT_WIDTH = $clog2(OVERSAMPLE);

    localparam integer BIT_CNT_WIDTH = (UART_DATA_WIDTH <= 1) ? 1 : $clog2(UART_DATA_WIDTH);

    localparam [31:0] HALF_SAMPLE_COUNT_FULL = OVERSAMPLE / 2 - 1;
    localparam [31:0] LAST_SAMPLE_COUNT_FULL = OVERSAMPLE - 1;
    localparam [SAMPLE_CNT_WIDTH-1:0] HALF_SAMPLE_COUNT = HALF_SAMPLE_COUNT_FULL[SAMPLE_CNT_WIDTH-1:0];
    localparam [SAMPLE_CNT_WIDTH-1:0] LAST_SAMPLE_COUNT = LAST_SAMPLE_COUNT_FULL[SAMPLE_CNT_WIDTH-1:0];

    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_STOP  = 3'd3;
    localparam [2:0] RX_DONE  = 3'd4;

    localparam [31:0] LAST_DATA_BIT_FULL = UART_DATA_WIDTH - 1;
    localparam [BIT_CNT_WIDTH-1:0] LAST_DATA_BIT = LAST_DATA_BIT_FULL[BIT_CNT_WIDTH-1:0];

    initial begin
        if ((UART_DATA_WIDTH < 5) || (UART_DATA_WIDTH > 9))
            $error("uart_rx UART_DATA_WIDTH must be between 5 and 9");

        if ((OVERSAMPLE < 4) || ((OVERSAMPLE % 2) != 0))
            $error("uart_rx OVERSAMPLE must be even and >= 4");
    end

    reg [2:0] rx_state;
    reg [UART_DATA_WIDTH-1:0] rx_shift;
    reg [BIT_CNT_WIDTH-1:0] bit_cnt;
    reg [SAMPLE_CNT_WIDTH-1:0] sample_cnt;

    // UART输入相对系统时钟异步，先做两级同步。
    reg rx_sync1;
    reg rx_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_shift    <= {UART_DATA_WIDTH{1'b0}};
            bit_cnt     <= {BIT_CNT_WIDTH{1'b0}};
            sample_cnt  <= {SAMPLE_CNT_WIDTH{1'b0}};
            rx_data     <= {UART_DATA_WIDTH{1'b0}};
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            frame_error <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_sync2 == 1'b0) begin   // 检测到起始位
                        bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
                        sample_cnt  <= {SAMPLE_CNT_WIDTH{1'b0}};
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (sample_tick) begin
                        if (sample_cnt == HALF_SAMPLE_COUNT) begin
                            sample_cnt <= {SAMPLE_CNT_WIDTH{1'b0}};

                            if (rx_sync2 == 1'b0) begin     // 确认起始位仍然为低电平
                                bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
                                rx_state <= RX_DATA;
                            end else begin
                                rx_state <= RX_IDLE;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                RX_DATA: begin
                    if (sample_tick) begin
                        if (sample_cnt == LAST_SAMPLE_COUNT) begin
                            sample_cnt <= {SAMPLE_CNT_WIDTH{1'b0}};
                            rx_shift[bit_cnt] <= rx_sync2;

                            if (bit_cnt == LAST_DATA_BIT) begin
                                bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
                                rx_state <= RX_STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                RX_STOP: begin
                    if (sample_tick) begin
                        if (sample_cnt == LAST_SAMPLE_COUNT) begin
                            sample_cnt  <= {SAMPLE_CNT_WIDTH{1'b0}};
                            rx_data     <= rx_shift;
                            rx_valid    <= 1'b1;
                            frame_error <= ~rx_sync2;  // 如果stop bit不是高电平，则表示帧错误。
                            rx_state    <= RX_DONE;
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end
                end

                RX_DONE: begin
                    // 保持rx_data和rx_valid，直到下游接收。
                    if (rx_ready) begin
                        rx_valid <= 1'b0;
                        rx_state <= RX_IDLE;
                    end
                end

                default: begin
                    rx_state <= RX_IDLE;
                    rx_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
