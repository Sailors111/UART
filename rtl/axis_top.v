module axis_top #(
    parameter integer UART_CLK_FREQ_HZ  = 100_000_000,
    parameter integer BAUD_RATE         = 115_200,
    parameter integer OVERSAMPLE        = 16,

    parameter integer AXIS_DATA_WIDTH   = 32,
    parameter integer UART_DATA_WIDTH   = 8,
    parameter integer AXIS_KEEP_WIDTH   = AXIS_DATA_WIDTH / 8,

    parameter integer TX_FIFO_DEPTH     = 16,
    parameter integer RX_FIFO_DEPTH     = 16,
    parameter integer RX_PACKET_LEN     = 16,
    parameter integer RX_TIMEOUT_CYCLES = 100_000
)(
    input  wire                         axis_clk,
    input  wire                         uart_clk,
    input  wire                         rst_n,

    input  wire                         rx,
    output wire                         tx,

    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                         s_axis_tlast,

    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0]   m_axis_tkeep,
    output wire                         m_axis_tlast
);

    wire baud_tick;
    wire sample_tick;

    wire                       tx_wr_valid;
    wire [UART_DATA_WIDTH-1:0] tx_wr_data;
    wire                       tx_wr_ready;

    wire                       tx_valid;
    wire [UART_DATA_WIDTH-1:0] tx_data;
    wire                       tx_ready;

    wire                       rx_valid;
    wire [UART_DATA_WIDTH-1:0] rx_data;
    wire                       rx_ready;

    wire                       rx_rd_valid;
    wire [UART_DATA_WIDTH-1:0] rx_rd_data;
    wire                       rx_rd_ready;

    baud_gen #(
        .CLK_FREQ   (UART_CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baud_gen (
        .clk         (uart_clk),
        .rst_n       (rst_n),
        .baud_tick   (baud_tick),
        .sample_tick (sample_tick)
    );

    axis_tx #(
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .UART_DATA_WIDTH (UART_DATA_WIDTH),
        .AXIS_KEEP_WIDTH (AXIS_KEEP_WIDTH)
    ) u_axis_tx (
        .clk           (axis_clk),
        .rst_n         (rst_n),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tkeep  (s_axis_tkeep),
        .s_axis_tlast  (s_axis_tlast),
        .tx_wr_valid   (tx_wr_valid),
        .tx_wr_ready   (tx_wr_ready),
        .tx_wr_data    (tx_wr_data)
    );

    async_fifo #(
        .DATA_WIDTH (UART_DATA_WIDTH),
        .DEPTH      (TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .wr_clk   (axis_clk),
        .wr_rst_n (rst_n),
        .rd_clk   (uart_clk),
        .rd_rst_n (rst_n),
        .wr_valid (tx_wr_valid),
        .wr_data  (tx_wr_data),
        .wr_ready (tx_wr_ready),
        .rd_valid (tx_valid),
        .rd_data  (tx_data),
        .rd_ready (tx_ready),
        .full     (),
        .empty    ()
    );

    uart_tx #(
        .UART_DATA_WIDTH (UART_DATA_WIDTH)
    ) u_uart_tx (
        .clk       (uart_clk),
        .rst_n     (rst_n),
        .baud_tick (baud_tick),
        .tx_valid  (tx_valid),
        .tx_data   (tx_data),
        .tx_ready  (tx_ready),
        .tx        (tx)
    );

    uart_rx #(
        .UART_DATA_WIDTH (UART_DATA_WIDTH),
        .OVERSAMPLE      (OVERSAMPLE)
    ) u_uart_rx (
        .clk         (uart_clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick),
        .rx          (rx),
        .rx_ready    (rx_ready),
        .rx_data     (rx_data),
        .rx_valid    (rx_valid),
        .frame_error ()
    );

    async_fifo #(
        .DATA_WIDTH (UART_DATA_WIDTH),
        .DEPTH      (RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .wr_clk   (uart_clk),
        .wr_rst_n (rst_n),
        .rd_clk   (axis_clk),
        .rd_rst_n (rst_n),
        .wr_valid (rx_valid),
        .wr_data  (rx_data),
        .wr_ready (rx_ready),
        .rd_valid (rx_rd_valid),
        .rd_data  (rx_rd_data),
        .rd_ready (rx_rd_ready),
        .full     (),
        .empty    ()
    );

    axis_rx #(
        .AXIS_DATA_WIDTH   (AXIS_DATA_WIDTH),
        .UART_DATA_WIDTH   (UART_DATA_WIDTH),
        .AXIS_KEEP_WIDTH   (AXIS_KEEP_WIDTH),
        .RX_PACKET_LEN     (RX_PACKET_LEN),
        .RX_TIMEOUT_CYCLES (RX_TIMEOUT_CYCLES)
    ) u_axis_rx (
        .clk           (axis_clk),
        .rst_n         (rst_n),
        .rx_rd_valid   (rx_rd_valid),
        .rx_rd_ready   (rx_rd_ready),
        .rx_rd_data    (rx_rd_data),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tkeep  (m_axis_tkeep),
        .m_axis_tlast  (m_axis_tlast)
    );

endmodule
