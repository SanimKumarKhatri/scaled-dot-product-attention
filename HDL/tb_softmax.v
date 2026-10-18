module tb_softmax;
    localparam N = 2;

    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst_n = 0;
    reg  start = 0;
    wire busy, done;

    reg signed [15:0] s_mem [0:N*N-1];
    reg signed [17:0] a_mem [0:N*N-1];

    wire [$clog2(N*N)-1:0] s_rd_addr;
    wire signed [15:0] s_rd_data;
    wire [$clog2(N*N)-1:0] a_wr_addr;
    wire signed [17:0] a_wr_data;
    wire a_wr_we;

    assign s_rd_data = s_mem[s_rd_addr];

    always @(posedge clk) begin
        if (a_wr_we) a_mem[a_wr_addr] <= a_wr_data;
    end

    softmax_unit #(.N(N)) dut (.clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
    .s_read_address(s_rd_addr), .s_read_data(s_rd_data), .a_write_address(a_wr_addr), .a_write_data(a_wr_data), .a_write_enable(a_wr_we));

    task run_softmax;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            wait (done == 1);
            @(negedge clk);
        end
    endtask

    integer i, j;
    
    initial begin
        $readmemh("../input/s.txt", s_mem);

        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        run_softmax;

        $display("--- A (Q1.15) ---");
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1)
                $write("%8d ", $signed(a_mem[i*N + j]));
            $write("\n");
        end

        $display("Tets Done!");
        $finish;
    end

    initial begin
        $dumpfile("tb_softmax.vcd");
        $dumpvars(0, tb_softmax);
    end
    
endmodule
