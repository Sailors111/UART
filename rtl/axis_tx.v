// rtl/axis_tx.v
// AXI-Stream宽度转换：将一个AXIS beat拆分成多个UART字节。
// 当前UART数据宽度限定为8位，低字节优先发送。
// UART线上没有包边界信息，因此s_axis_tlast不向后级传输。

module axis_tx #(
    parameter integer AXIS_DATA_WIDTH = 32,
    parameter integer UART_DATA_WIDTH  = 8,
    parameter integer AXIS_KEEP_WIDTH  = AXIS_DATA_WIDTH / 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                         s_axis_tlast,

    output wire                         tx_wr_valid,
    input  wire                         tx_wr_ready,
    output wire [UART_DATA_WIDTH-1:0]   tx_wr_data
);

    localparam integer BYTE_INDEX_WIDTH =
        (AXIS_KEEP_WIDTH <= 1) ? 1 : $clog2(AXIS_KEEP_WIDTH);  // 字节索引的位宽

    localparam [1:0] TX_IDLE = 2'd0;
    localparam [1:0] TX_FIND = 2'd1;
    localparam [1:0] TX_SEND = 2'd2;

    reg [1:0] tx_state;
    reg [AXIS_DATA_WIDTH-1:0]  data_reg;
    reg [AXIS_KEEP_WIDTH-1:0]  keep_reg;
    reg [BYTE_INDEX_WIDTH-1:0] byte_index;          // 字节索引
    reg [BYTE_INDEX_WIDTH-1:0] last_byte_index;          // 最后一个字节索引

    initial begin
        if (AXIS_DATA_WIDTH <= 0 || (AXIS_DATA_WIDTH % 8) != 0)
            $error("axis_tx AXIS_DATA_WIDTH must be a positive multiple of 8");

        if (UART_DATA_WIDTH != 8)
            $error("axis_tx currently supports UART_DATA_WIDTH=8 only");

        if (AXIS_KEEP_WIDTH != AXIS_DATA_WIDTH / 8)
            $error("axis_tx AXIS_KEEP_WIDTH does not match AXIS_DATA_WIDTH");
    end

    // 返回TKEEP中最高有效字节的索引。
    function [BYTE_INDEX_WIDTH-1:0] find_last_index;
        input [AXIS_KEEP_WIDTH-1:0] keep_value;
        integer index;
        begin
            find_last_index = {BYTE_INDEX_WIDTH{1'b0}};
            for (index = 0; index < AXIS_KEEP_WIDTH; index = index + 1) begin
                if (keep_value[index])
                    find_last_index = index;
            end
        end
    endfunction

    assign s_axis_tready = (tx_state == TX_IDLE);

    // tx_wr_data在TX_SEND期间保持不变，直到下游完成握手。
    assign tx_wr_valid = (tx_state == TX_SEND);
    assign tx_wr_data  = data_reg >> (byte_index * UART_DATA_WIDTH);

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            data_reg   <= {AXIS_DATA_WIDTH{1'b0}};
            keep_reg   <= {AXIS_KEEP_WIDTH{1'b0}};
            byte_index <= {BYTE_INDEX_WIDTH{1'b0}};
            last_byte_index <= {BYTE_INDEX_WIDTH{1'b0}};
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (s_axis_tvalid) begin
                        data_reg   <= s_axis_tdata;
                        keep_reg   <= s_axis_tkeep;
                        byte_index <= {BYTE_INDEX_WIDTH{1'b0}};
                        last_byte_index <= find_last_index(s_axis_tkeep);
                        tx_state   <= TX_FIND;
                    end
                end

                TX_FIND: begin
                    // 跳过TKEEP中无效的字节lane。
                    if (keep_reg[byte_index]) begin
                        tx_state <= TX_SEND;
                    end else if (byte_index == AXIS_KEEP_WIDTH - 1) begin
                        // TKEEP全为0时，该beat没有可发送的字节。
                        tx_state <= TX_IDLE;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end

                TX_SEND: begin
                    if (tx_wr_ready) begin
                        if (byte_index == last_byte_index) begin
                            byte_index <= {BYTE_INDEX_WIDTH{1'b0}};
                            tx_state   <= TX_IDLE;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            tx_state   <= TX_FIND;
                        end
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

endmodule
