`timescale 1ns/1ps

// Test 02: asynchronous FIFO stress test.
// The write clock is eleven times faster than the read clock. The test forces
// full/empty conditions, repeatedly wraps both pointers, and checks ordering.
module tb_test02;

    localparam integer DATA_WIDTH = 8;
    localparam integer FIFO_DEPTH = 4;

    reg wr_clock;
    reg rd_clock;
    reg reset;
    wire rst_n = ~reset;

    reg                   wr_valid;
    reg  [DATA_WIDTH-1:0] wr_data;
    wire                  wr_ready;
    wire                  rd_valid;
    reg                   rd_ready;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  full;
    wire                  empty;

    integer saw_full_wait;
    integer saw_empty_wait;

    always #1  wr_clock = ~wr_clock;
    always #11 rd_clock = ~rd_clock;

    initial begin
        $dumpfile("wave/tb_test02.vcd");
        $dumpvars(0, tb_test02);
    end

    task automatic reset_fifo;
        begin
            wr_valid <= 1'b0;
            wr_data  <= 8'd0;
            rd_ready <= 1'b0;
            reset    <= 1'b1;
            repeat (3) @(posedge wr_clock);
            repeat (3) @(posedge rd_clock);
            reset <= 1'b0;
            repeat (3) @(posedge wr_clock);
            repeat (3) @(posedge rd_clock);

            if (full !== 1'b0 || wr_ready !== 1'b1)
                $fatal(1, "FIFO write side did not reset");
            if (empty !== 1'b1 || rd_valid !== 1'b0)
                $fatal(1, "FIFO read side did not reset");
        end
    endtask

    task automatic write_byte;
        input [7:0] value;
        output integer waited;
        begin
            @(negedge wr_clock);
            wr_data  <= value;
            wr_valid <= 1'b1;
            waited = 0;

            while (1) begin
                @(posedge wr_clock);
                if (wr_ready === 1'b1) begin
                    @(negedge wr_clock);
                    wr_valid <= 1'b0;
                    wr_data  <= 8'd0;
                    disable write_byte;
                end
                if (full !== 1'b1)
                    $fatal(1, "wr_ready low without full");
                waited = waited + 1;
                if (waited >= 10000)
                    $fatal(1, "write timeout");
            end
        end
    endtask

    task automatic read_byte;
        input [7:0] expected;
        output integer waited;
        reg [7:0] value;
        begin
            @(negedge rd_clock);
            rd_ready <= 1'b1;
            waited = 0;

            while (1) begin
                @(posedge rd_clock);
                if (rd_valid === 1'b1) begin
                    value = rd_data;
                    if (value !== expected)
                        $fatal(1, "FIFO order mismatch: expected %02x, got %02x",
                            expected, value);
                    @(negedge rd_clock);
                    rd_ready <= 1'b0;
                    disable read_byte;
                end
                if (empty !== 1'b1)
                    $fatal(1, "rd_valid low without empty");
                waited = waited + 1;
                if (waited >= 10000)
                    $fatal(1, "read timeout");
            end
        end
    endtask

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) dut (
        .wr_clk   (wr_clock),
        .wr_rst_n (rst_n),
        .rd_clk   (rd_clock),
        .rd_rst_n (rst_n),
        .wr_valid (wr_valid),
        .wr_data  (wr_data),
        .wr_ready (wr_ready),
        .rd_valid (rd_valid),
        .rd_data  (rd_data),
        .rd_ready (rd_ready),
        .full     (full),
        .empty    (empty)
    );

    integer index;
    integer waited;

    initial begin
        wr_clock = 1'b0;
        rd_clock = 1'b0;
        reset    = 1'b1;
        wr_valid = 1'b0;
        wr_data  = 8'd0;
        rd_ready = 1'b0;
        saw_full_wait  = 0;
        saw_empty_wait = 0;

        reset_fifo();

        fork
            begin
                for (index = 0; index < 32; index = index + 1) begin
                    write_byte((8'h10 + index * 7) & 8'hff, waited);
                    if (waited > 0)
                        saw_full_wait = 1;
                end
            end
            begin : fast_write_slow_read
                integer read_index;
                integer read_waited;
                repeat (8) @(posedge rd_clock);
                for (read_index = 0; read_index < 32; read_index = read_index + 1)
                    read_byte((8'h10 + read_index * 7) & 8'hff, read_waited);
            end
        join

        repeat (4) @(posedge rd_clock);
        if (!saw_full_wait)
            $fatal(1, "extreme clock ratio never produced full backpressure");
        if (empty !== 1'b1)
            $fatal(1, "FIFO not empty after fast-write case");
        $display("PASS: fast write / slow read crossed full and wrapped pointers");

        reset_fifo();

        fork
            begin : slow_writer
                integer write_index;
                integer write_waited;
                for (write_index = 0; write_index < 12; write_index = write_index + 1) begin
                    repeat (40) @(posedge wr_clock);
                    write_byte(8'h80 + write_index, write_waited);
                end
            end
            begin : fast_reader
                integer read_index;
                integer read_waited;
                for (read_index = 0; read_index < 12; read_index = read_index + 1) begin
                    read_byte(8'h80 + read_index, read_waited);
                    if (read_waited > 0)
                        saw_empty_wait = 1;
                end
            end
        join

        repeat (4) @(posedge rd_clock);
        if (!saw_empty_wait)
            $fatal(1, "slow writer never produced an empty wait");
        if (empty !== 1'b1)
            $fatal(1, "FIFO not empty after slow-write case");

        $display("PASS: slow write / waiting read crossed empty repeatedly");
        $display("TEST02 PASS: asynchronous FIFO extreme-clock stress");
        $finish;
    end

    initial begin
        #500_000;
        $fatal(1, "test02 timeout");
    end

endmodule
