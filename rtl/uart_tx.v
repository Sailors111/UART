
// rtl/uart_tx.v    UART发送模块：core的数据发送到外设


module uart_tx #(
    parameter integer UART_DATA_WIDTH = 8
)(
    input  wire                  clk,        // 系统时钟
    input  wire                  rst_n,      // 低有效复位

    input  wire                  baud_tick,  // 波特率tick，每到一个tick发送1bit

    input  wire                  tx_valid,   // 发送请求
    input  wire [UART_DATA_WIDTH-1:0] tx_data,    // 要发送的数据
    output wire                  tx_ready,

    output reg                   tx          // UART发送线
);

    localparam integer BIT_CNT_WIDTH = (UART_DATA_WIDTH <= 1) ? 1 : $clog2(UART_DATA_WIDTH);

    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    localparam [31:0] LAST_DATA_BIT_FULL = UART_DATA_WIDTH - 1;
    localparam [BIT_CNT_WIDTH-1:0] LAST_DATA_BIT = LAST_DATA_BIT_FULL[BIT_CNT_WIDTH-1:0];

    initial begin
        if ((UART_DATA_WIDTH < 5) || (UART_DATA_WIDTH > 9))
            $error("uart_tx UART_DATA_WIDTH must be between 5 and 9");
    end

    reg [1:0] tx_state;
    reg [UART_DATA_WIDTH-1:0] tx_shift;
    reg [BIT_CNT_WIDTH-1:0] bit_cnt;

    assign tx_ready = (tx_state == TX_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_shift <= {UART_DATA_WIDTH{1'b0}};
            bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
            tx       <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;         // UART高电平空闲

                    if (tx_valid) begin
                        tx_shift <= tx_data;
                        bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        tx       <= 1'b0;       // UART低电平忙碌
                        tx_state <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        tx <= tx_shift[0];

                        if (bit_cnt == LAST_DATA_BIT) begin
                            bit_cnt  <= {BIT_CNT_WIDTH{1'b0}};
                            tx_state <= TX_STOP;
                        end else begin
                            tx_shift <= tx_shift >> 1;
                            bit_cnt  <= bit_cnt + 1'b1;
                        end
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        tx       <= 1'b1;
                        tx_state <= TX_IDLE;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                    tx       <= 1'b1;
                end
            endcase
        end
    end

endmodule
