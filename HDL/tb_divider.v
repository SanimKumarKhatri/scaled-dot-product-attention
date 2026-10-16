module tb_divider;
    localparam WIDTH = 32;

    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst_n = 0;
    reg  start = 0;
    reg  [WIDTH-1:0] dividend = 0;
    reg  [WIDTH-1:0] divisor  = 0;
    wire [WIDTH-1:0] quotient;
    wire busy, done;

    divider #(.WIDTH(WIDTH)) dut (.clk(clk), .rst_n(rst_n), .start(start),
    .dividend(dividend), .divisor(divisor), .quotient(quotient), .busy(busy), .done(done));

    task run_div(input [WIDTH-1:0] n, input [WIDTH-1:0] d, input [WIDTH-1:0] exp);
        begin
            @(negedge clk);
            dividend = n;
            divisor  = d;
            start    = 1;
            @(negedge clk);
            start    = 0;
            wait (done == 1);
            @(negedge clk);
            if (quotient !== exp)
                $display("FAIL: %0d / %0d = %0d, expected %0d", n, d, quotient, exp);
            else
                $display("PASS: %0d / %0d = %0d", n, d, quotient);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        run_div(32'd100,         32'd2,     32'd50);
        run_div(32'd1024,        32'd4,     32'd256);
        run_div(32'd17,          32'd17,    32'd1);
        run_div(32'd3,           32'd7,     32'd0);
        run_div(32'd1073741824,  32'd65536, 32'd16384);

        $display("Tets Done!");
        $finish;
    end
endmodule