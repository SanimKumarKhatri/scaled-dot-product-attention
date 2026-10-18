`timescale 1ns/1ps
module tb_loop_ctrl;
    localparam NI = 2, NJ = 4, NK = 2, JSTEP = 1;

    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst_n = 0;
    reg  start = 0;

    wire [((NI>1)?$clog2(NI):1)-1:0] i;
    wire [((NJ>1)?$clog2(NJ):1)-1:0] j;
    wire [((NK>1)?$clog2(NK):1)-1:0]   k;
    wire mac_clear, mac_enable, write_enable, busy, done;

    loop_control #(.NI(NI), .NJ(NJ), .NK(NK), .JSTEP(JSTEP)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .i(i), .j(j), .k(k),
        .mac_clear(mac_clear), .mac_enable(mac_enable),
        .write_enable(write_enable),
        .busy(busy), .done(done)
    );

    // print every cycle
    always @(posedge clk) begin
        $display("t=%0t state=%0d i=%0d j=%0d k=%0d clr=%b en=%b we=%b busy=%b done=%b",
                 $time, dut.state, i, j, k,
                 mac_clear, mac_enable, write_enable, busy, done);
    end

    initial begin
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        repeat (40) @(negedge clk);
        $finish;
    end
endmodule
