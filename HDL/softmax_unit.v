// softmax unit

module softmax_unit #(
    parameter N = 2,
    parameter LUT_FILE = "../input/exp_lut.hex"
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    output wire [$clog2(N*N)-1:0] s_read_address,
    input wire signed [15:0] s_read_data,

    output wire [$clog2(N*N)-1:0] a_write_address,
    output wire signed [17:0] a_write_data,
    output wire a_write_enable,

    output reg busy,
    output reg done
);
    localparam [2:0]    SM_IDLE = 3'd0,
                        SM_MAX = 3'd1,
                        SM_EXP = 3'd2,
                        SM_DIV = 3'd3,
                        SM_DIV_WAIT = 3'd4,
                        SM_NORM = 3'd5,
                        SM_FINISHED = 3'd6;

    localparam I_W = ($clog2(N) < 1) ? 1 : $clog2(N);
    localparam ESUM_W = $clog2(N) + 16;

    reg [2:0] state;

    reg [I_W-1:0] i;
    reg [I_W-1:0] j;

    reg signed [17:0] smax;
    reg [ESUM_W-1:0] esum;
    reg [16:0] inv;
    reg [15:0] ebuf [0:N-1];

    reg [15:0] exp_lut [0:255];
    initial $readmemh(LUT_FILE, exp_lut);

    localparam signed [18:0] LOG2E_Q14 = 19'sd23637;

    wire signed [17:0] s_cur = s_read_data;
    wire signed [18:0] dlt = s_cur - smax;
    wire signed [37:0] tprod = dlt * LOG2E_Q14;
    wire signed [37:0] tsh = tprod >>> 14;
    wire signed [37:0] negt = -tsh;
    wire [19:0] uexp = negt[19:0];
    wire [11:0] ip = uexp[19:8]; 
    wire [7:0]  fp = uexp[7:0];
    wire [15:0] lutv = exp_lut[fp];
    wire [15:0] eval = (ip >= 12'd16) ? 16'd0 : (lutv >> ip);

    wire [32:0] wprod = ebuf[j] * inv;
    wire [32:0] wsum  = wprod + 33'd16384;
    wire [17:0] wval  = wsum[32:15];

    assign s_read_address = i*N + j;
    assign a_write_address = i*N + j;
    assign a_write_data = wval;
    assign a_write_enable   = (state == SM_NORM);

    wire div_done;
    wire [31:0] div_quo;
    wire div_start = (state == SM_DIV);

    divider #(.WIDTH(32)) u_div (.clk(clk), .rst_n(rst_n), .start(div_start),
    .dividend(32'h4000_0000), .divisor({{(32-ESUM_W){1'b0}}, esum}), .quotient(div_quo), .busy(), .done(div_done));
    
    always @(posedge clk) begin
        if (!rst_n) begin
            i <= 0;
            j <= 0;
            smax <= 0;
            esum <= 0;
            inv <= 0;
            done <= 1'b0;
            busy <= 1'b0;
            state <= SM_IDLE;
        end
        else begin
            done <= 1'b0;

            case(state)
                SM_IDLE: if (start) begin
                    i <= 0;
                    j <= 0;
                    smax <= 0;
                    esum <= 0;
                    inv <= 0;
                    busy <= 1'b1;
                    state <= SM_MAX;
                end

                SM_MAX: begin
                    if (j == 0) smax <= s_cur;
                    else if (s_cur > smax) smax <= s_cur;
                    if (j == N-1) begin
                        j <= 0;
                        state <= SM_EXP;
                    end else begin
                        j <= j + 1;
                    end
                end

                SM_EXP: begin
                    ebuf[j] <= eval;
                    esum <= esum + eval;
                    if (j == N-1) begin
                        j <= 0;
                        state <= SM_DIV;
                    end else begin
                        j <= j + 1;
                    end
                end

                SM_DIV: begin
                    state <= SM_DIV_WAIT;
                end

                SM_DIV_WAIT: begin
                    if (div_done) begin
                       inv <= div_quo[16:0];
                       state <= SM_NORM; 
                    end
                end

                SM_NORM: begin
                    if (j == N-1) begin
                        j <= 0;
                        if (i == N-1) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= SM_FINISHED;
                        end else begin
                            i     <= i + 1;
                            esum  <= 0;
                            state <= SM_MAX;
                        end
                    end else begin
                        j <= j + 1;
                    end
                end

                SM_FINISHED: begin
                    state <= SM_IDLE;
                end

            endcase
        end
    end
endmodule
