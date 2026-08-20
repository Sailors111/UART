`timescale 1ns/1ps

// Test 00: two UART IPs exchange one byte in both directions.
// dut0 sends 0x55 to dut1; dut1 checks it and sends it back; dut0 checks it.
module tb_test00;

    localparam integer AXIS_DATA_WIDTH   = 32;
    localparam integer UART_DATA_WIDTH   = 8;
    localparam integer AXIS_KEEP_WIDTH   = 4;
    localparam integer UART_CLK_FREQ_HZ  = 80_000_000;
    localparam integer BAUD_RATE         = 5_000_000;
    localparam integer OVERSAMPLE        = 16;
    localparam integer RX_TIMEOUT_CYCLES = 128;

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

    always #5    axis_clock = ~axis_clock;
    always #6.25 uart_clock = ~uart_clock;

    initial begin
        $dumpfile("wave/tb_test00.vcd");
        $dumpvars(0, tb_test00);
    end

    task automatic send_dut0;
        input [7:0] data;
        integer cycles;
        begin
            @(posedge axis_clock);
            s_axis_tdata_0  <= {24'd0, data};
            s_axis_tkeep_0  <= 4'b0001;
            s_axis_tlast_0  <= 1'b1;
            s_axis_tvalid_0 <= 1'b1;

            cycles = 0;
            while (1) begin
                @(posedge axis_clock);
                if (s_axis_tready_0 === 1'b1) begin
                    s_axis_tvalid_0 <= 1'b0;
                    s_axis_tdata_0  <= 32'd0;
                    s_axis_tkeep_0  <= 4'd0;
                    s_axis_tlast_0  <= 1'b0;
                    disable send_dut0;
                end
                cycles = cycles + 1;
                if (cycles >= 10000)
                    $fatal(1, "dut0 send timeout");
            end
        end
    endtask

    task automatic send_dut1;
        input [7:0] data;
        integer cycles;
        begin
            @(posedge axis_clock);
            s_axis_tdata_1  <= {24'd0, data};
            s_axis_tkeep_1  <= 4'b0001;
            s_axis_tlast_1  <= 1'b1;
            s_axis_tvalid_1 <= 1'b1;

            cycles = 0;
            while (1) begin
                @(posedge axis_clock);
                if (s_axis_tready_1 === 1'b1) begin
                    s_axis_tvalid_1 <= 1'b0;
                    s_axis_tdata_1  <= 32'd0;
                    s_axis_tkeep_1  <= 4'd0;
                    s_axis_tlast_1  <= 1'b0;
                    disable send_dut1;
                end
                cycles = cycles + 1;
                if (cycles >= 10000)
                    $fatal(1, "dut1 send timeout");
            end
        end
    endtask

    task automatic receive_dut1;
        output [7:0] data;
        integer cycles;
        begin
            cycles = 0;
            while (m_axis_tvalid_1 !== 1'b1) begin
                @(posedge axis_clock);
                cycles = cycles + 1;
                if (cycles >= 100000)
                    $fatal(1, "dut1 receive timeout");
            end

            data = m_axis_tdata_1[7:0];
            if (m_axis_tkeep_1 !== 4'b0001)
                $fatal(1, "dut1 TKEEP mismatch: %b", m_axis_tkeep_1);
            if (m_axis_tlast_1 !== 1'b1)
                $fatal(1, "dut1 TLAST mismatch");

            @(posedge axis_clock);
            m_axis_tready_1 <= 1'b1;
            @(posedge axis_clock);
            m_axis_tready_1 <= 1'b0;
        end
    endtask

    task automatic receive_dut0;
        output [7:0] data;
        integer cycles;
        begin
            cycles = 0;
            while (m_axis_tvalid_0 !== 1'b1) begin
                @(posedge axis_clock);
                cycles = cycles + 1;
                if (cycles >= 100000)
                    $fatal(1, "dut0 receive timeout");
            end

            data = m_axis_tdata_0[7:0];
            if (m_axis_tkeep_0 !== 4'b0001)
                $fatal(1, "dut0 TKEEP mismatch: %b", m_axis_tkeep_0);
            if (m_axis_tlast_0 !== 1'b1)
                $fatal(1, "dut0 TLAST mismatch");

            @(posedge axis_clock);
            m_axis_tready_0 <= 1'b1;
            @(posedge axis_clock);
            m_axis_tready_0 <= 1'b0;
        end
    endtask

    axis_top #(
        .UART_CLK_FREQ_HZ  (UART_CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .OVERSAMPLE        (OVERSAMPLE),
        .AXIS_DATA_WIDTH   (AXIS_DATA_WIDTH),
        .UART_DATA_WIDTH   (UART_DATA_WIDTH),
        .AXIS_KEEP_WIDTH   (AXIS_KEEP_WIDTH),
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

    reg [7:0] dut1_data;
    reg [7:0] dut0_data;

    initial begin
        axis_clock = 1'b0;
        uart_clock = 1'b0;
        reset      = 1'b1;

        s_axis_tvalid_0 = 1'b0;
        s_axis_tdata_0  = 32'd0;
        s_axis_tkeep_0  = 4'd0;
        s_axis_tlast_0  = 1'b0;
        m_axis_tready_0 = 1'b0;

        s_axis_tvalid_1 = 1'b0;
        s_axis_tdata_1  = 32'd0;
        s_axis_tkeep_1  = 4'd0;
        s_axis_tlast_1  = 1'b0;
        m_axis_tready_1 = 1'b0;

        repeat (20) @(posedge axis_clock);
        reset <= 1'b0;
        repeat (5) @(posedge axis_clock);

        send_dut0(8'h55);
        receive_dut1(dut1_data);
        if (dut1_data !== 8'h55)
            $fatal(1, "dut1 expected 0x55, got 0x%02x", dut1_data);
        $display("PASS: dut1 received 0x%02x", dut1_data);

        send_dut1(dut1_data);
        receive_dut0(dut0_data);
        if (dut0_data !== 8'h55)
            $fatal(1, "dut0 expected 0x55, got 0x%02x", dut0_data);
        $display("PASS: dut0 received loopback 0x%02x", dut0_data);

        $display("TEST00 PASS: one-byte bidirectional loopback");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "test00 timeout");
    end

endmodule
