`timescale 1ns/1ps
module tb_attention;
    localparam N     = 2;
    localparam DM    = 4;
    localparam DK    = 4;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg start = 0;

    reg                load_en   = 0;
    reg [1:0]          load_sel  = 0;
    reg [15:0]         load_addr = 0;
    reg signed [15:0]  load_data = 0;

    reg  [15:0]        rd_addr = 0;
    wire signed [15:0] rd_data;
    wire               busy, done;
    wire [31:0]        cycles;

    attention #(
        .N(N), .DM(DM), .DK(DK),
        .LUT_FILE("../input/exp_lut.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .load_en(load_en), .load_sel(load_sel),
        .load_address(load_addr), .load_data(load_data),
        .read_address(rd_addr), .read_data(rd_data),
        .busy(busy), .done(done), .cycles(cycles)
    );

    integer i, j;
    integer idx;
    reg signed [15:0] tmp [0:15]; 

    task load_word(input [1:0] sel, input [15:0] addr, input signed [15:0] data);
        begin
            @(negedge clk);
            load_en   = 1;
            load_sel  = sel;
            load_addr = addr;
            load_data = data;
            @(negedge clk);
            load_en   = 0;
        end
    endtask

    task run_attention;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            wait (done == 1);
            @(negedge clk);
        end
    endtask

    initial begin
        // ---- reset ----
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // ---- load X ----
        $readmemh("../input/x.txt", tmp);
        for (idx = 0; idx < N*DM; idx = idx + 1)
            load_word(2'd0, idx[15:0], tmp[idx]);

        // ---- load Wq ----
        $readmemh("../input/wq.txt", tmp);
        for (idx = 0; idx < DM*DK; idx = idx + 1)
            load_word(2'd1, idx[15:0], tmp[idx]);

        // ---- load Wk ----
        $readmemh("../input/wk.txt", tmp);
        for (idx = 0; idx < DM*DK; idx = idx + 1)
            load_word(2'd2, idx[15:0], tmp[idx]);

        // ---- load Wv ----
        $readmemh("../input/wv.txt", tmp);
        for (idx = 0; idx < DM*DK; idx = idx + 1)
            load_word(2'd3, idx[15:0], tmp[idx]);

        // ---- run ----
        run_attention;

        $display("cycles = %0d", cycles);
        $display("--- O ---");
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < DK; j = j + 1) begin
                rd_addr = i*DK + j;
                #1;
                $write("%8d ", $signed(rd_data));
            end
            $write("\n");
        end

        $display("done.");
        $finish;
    end

    initial begin
        $dumpfile("tb_attention.vcd");
        $dumpvars(0, tb_attention);
    end
endmodule