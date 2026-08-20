module baud_gen #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
)(
    input  wire clk,
    input  wire rst_n,

    output reg  baud_tick,
    output reg  sample_tick
);

    localparam integer SAMPLE_RATE = BAUD_RATE * OVERSAMPLE;

    initial begin
        if (CLK_FREQ <= 0)
            $error("baud_gen CLK_FREQ must be greater than 0");

        if (BAUD_RATE <= 0)
            $error("baud_gen BAUD_RATE must be greater than 0");

        if ((OVERSAMPLE < 4) || ((OVERSAMPLE % 2) != 0))
            $error("baud_gen OVERSAMPLE must be even and >= 4");

        if (SAMPLE_RATE > CLK_FREQ)
            $error("baud_gen BAUD_RATE * OVERSAMPLE must not exceed CLK_FREQ");
    end

    reg [31:0] sample_acc;
    reg [31:0] sample_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_acc  <= 32'd0;
            sample_cnt  <= 32'd0;
            baud_tick   <= 1'b0;
            sample_tick <= 1'b0;
        end else begin
            baud_tick   <= 1'b0;
            sample_tick <= 1'b0;

            if (sample_acc + SAMPLE_RATE >= CLK_FREQ) begin
                sample_acc  <= sample_acc + SAMPLE_RATE - CLK_FREQ;
                sample_tick <= 1'b1;

                if (sample_cnt == OVERSAMPLE - 1) begin
                    sample_cnt <= 32'd0;
                    baud_tick  <= 1'b1;
                end else begin
                    sample_cnt <= sample_cnt + 32'd1;
                end
            end else begin
                sample_acc <= sample_acc + SAMPLE_RATE;
            end
        end
    end

endmodule
