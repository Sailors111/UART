

module async_fifo #(
    parameter integer DATA_WIDTH = 8,   // FIFO队列中每个元素的位宽
    parameter integer DEPTH      = 16   // FIFO队列的容量，必须为2的幂
)(
    input  wire                  wr_clk,        // 写时钟
    input  wire                  wr_rst_n,      // 写时钟复位，低有效

    input  wire                  rd_clk,        // 读时钟
    input  wire                  rd_rst_n,      // 读时钟复位，低有效

    input  wire                  wr_valid,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_ready,

    output wire                  rd_valid,
    output wire [DATA_WIDTH-1:0] rd_data,
    input  wire                  rd_ready,

    output wire                  full,
    output wire                  empty
);

    localparam integer ADDR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH + 1;

    // FULL_MASK最高两位为1，其余位为0。
    localparam [PTR_WIDTH-1:0] FULL_MASK = {2'b11, {(PTR_WIDTH-2){1'b0}}};

    initial begin
        if (DATA_WIDTH <= 0)
            $error("async_fifo DATA_WIDTH must be greater than 0");

        if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0))
            $error("async_fifo DEPTH must be a power of two and >= 2");
    end

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 二进制指针负责本时钟域计数和访问mem。
    reg [PTR_WIDTH-1:0] wr_bin;
    reg [PTR_WIDTH-1:0] rd_bin;

    // 格雷码指针负责跨时钟域。
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_gray;

    // 跨时钟同步
    reg [PTR_WIDTH-1:0] rd_gray_sync1;
    reg [PTR_WIDTH-1:0] rd_gray_sync2;
    reg [PTR_WIDTH-1:0] wr_gray_sync1;
    reg [PTR_WIDTH-1:0] wr_gray_sync2;

    reg full_reg;
    reg empty_reg;

    wire write_fire;
    wire read_fire;
    wire full_next;
    wire empty_next;

    wire [PTR_WIDTH-1:0] wr_bin_next;
    wire [PTR_WIDTH-1:0] wr_gray_next;
    wire [PTR_WIDTH-1:0] rd_bin_next;
    wire [PTR_WIDTH-1:0] rd_gray_next;

    assign full     = full_reg;
    assign empty    = empty_reg;

    assign wr_ready = ~ full_reg;
    assign rd_valid = ~ empty_reg;

    assign write_fire = wr_valid && wr_ready;   // 写有效
    assign read_fire  = rd_valid && rd_ready;   // 读有效

    assign wr_bin_next = wr_bin + {{(PTR_WIDTH-1){1'b0}}, write_fire};
    assign rd_bin_next = rd_bin + {{(PTR_WIDTH-1){1'b0}}, read_fire};

    // 格雷码计算公式：gray = (bin >> 1) ^ bin
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next; 
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // 写指针追上读指针时为满
    assign full_next  = (wr_gray_next == (rd_gray_sync2 ^ FULL_MASK));   
    // 读指针追上写指针时为空
    assign empty_next = (rd_gray_next == wr_gray_sync2);

    assign rd_data = mem[rd_bin[ADDR_WIDTH-1:0]];

    integer i;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin   <= {PTR_WIDTH{1'b0}};
            wr_gray  <= {PTR_WIDTH{1'b0}};
            full_reg <= 1'b0;
        end else begin
            wr_bin   <= wr_bin_next;
            wr_gray  <= wr_gray_next;
            full_reg <= full_next;

            if (write_fire) begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    mem[i] <= (wr_bin[ADDR_WIDTH-1:0] == i[ADDR_WIDTH-1:0]) ? wr_data : mem[i];
                end
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin    <= {PTR_WIDTH{1'b0}};
            rd_gray   <= {PTR_WIDTH{1'b0}};
            empty_reg <= 1'b1;
        end else begin
            rd_bin    <= rd_bin_next;
            rd_gray   <= rd_gray_next;
            empty_reg <= empty_next;
        end
    end

    // 读指针同步到写时钟域，供full判断使用。
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // 写指针同步到读时钟域，供empty判断使用。
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

endmodule
