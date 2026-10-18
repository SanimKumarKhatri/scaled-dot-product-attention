module attention #(
    parameter N = 2,
    parameter DM = 4,
    parameter DK = 4,
    parameter FRAC = 8,
    parameter ACC_W = 40,
    parameter LUT_FILE = "../input/exp_lut.hex"
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    input  wire load_en,
    input  wire [1:0] load_sel,
    input  wire [15:0] load_address,
    input  wire signed [15:0] load_data,

    input  wire [15:0] read_address,
    output wire signed [15:0] read_data,

    output reg busy,
    output reg done,
    output reg [31:0] cycles
);
    function integer log4;
        input integer v;
        integer t;
        begin
            t = v; log4 = 0;
            while (t > 1) begin t = t/4; log4 = log4 + 1; end
        end
    endfunction

    initial begin
        if (N < 2)   $fatal(1, "ERROR: attention: N must be >= 2");
        if (DM < 2)  $fatal(1, "ERROR: attention: DM must be >= 2");
        if (DK < 2)  $fatal(1, "ERROR: attention: DK must be >= 2");
        if ((1 << (2*log4(DK))) != DK)
            $fatal(1, "ERROR: attention: DK=%0d is not a power of 4", DK);
    end
    
    localparam IW_N = $clog2(N);
    localparam IW_DK = $clog2(DK);
    localparam IW_DM = $clog2(DM);

    //memory registers
    reg signed [15:0] x_mem [(N*DM)-1:0];
    reg signed [15:0] wq_mem [(DM*DK)-1:0];
    reg signed [15:0] wk_mem [(DM*DK)-1:0];
    reg signed [15:0] wv_mem [(DM*DK)-1:0];
    reg signed [15:0] q_mem [(N*DK)-1:0];
    reg signed [15:0] k_mem [(N*DK)-1:0];
    reg signed [15:0] v_mem [(N*DK)-1:0];
    reg signed [15:0] s_mem [(N*N)-1:0];
    reg signed [17:0] a_mem [(N*N)-1:0];
    reg signed [15:0] o_mem [(N*DK)-1:0];

    // loading data
    always @(posedge clk) begin
        if (load_en) begin
            case (load_sel)
                2'd0: x_mem[load_address] <= load_data;
                2'd1: wq_mem[load_address] <= load_data;
                2'd2: wk_mem[load_address] <= load_data;
                2'd3: wv_mem[load_address] <= load_data;
            endcase
        end
    end

    assign read_data = o_mem[read_address];

    // states
    localparam [2:0]    ATTN_IDLE = 3'd0,
                        ATTN_PH_QK = 3'd1,
                        ATTN_PH_SV = 3'd2,
                        ATTN_PH_SM = 3'd3,
                        ATTN_PH_O = 3'd4,
                        ATTN_DONE = 3'd5;

    reg [2:0] state;

    wire qk_start, s_start, v_start, o_start, sm_start;

    // u_qk wires
    wire [IW_N-1:0] qk_i;
    wire [IW_DK-1:0] qk_j;
    wire [IW_DM-1:0] qk_k;
    wire qk_mac_clear, qk_mac_enable, qk_write_enable;
    wire qk_busy, qk_done;

    loop_control #(.NI(N), .NJ(DK), .NK(DM), .JSTEP(1)) u_qk (
        .clk(clk), .rst_n(rst_n), .start(qk_start),
        .i(qk_i), .j(qk_j), .k(qk_k),
        .mac_clear(qk_mac_clear),
        .mac_enable(qk_mac_enable),
        .write_enable(qk_write_enable),
        .busy(qk_busy), .done(qk_done)
    );

    // u_s wires
    wire [IW_N-1:0] s_i;
    wire [IW_N-1:0] s_j;
    wire [IW_DK-1:0] s_k;
    wire s_mac_clear, s_mac_enable, s_write_enable;
    wire s_busy, s_done;

    loop_control #(.NI(N), .NJ(N), .NK(DK), .JSTEP(1)) u_s (
        .clk(clk), .rst_n(rst_n), .start(s_start),
        .i(s_i), .j(s_j), .k(s_k),
        .mac_clear(s_mac_clear),
        .mac_enable(s_mac_enable),
        .write_enable(s_write_enable),
        .busy(s_busy), .done(s_done)
    );

    // u_v wires
    wire [IW_N-1:0] v_i;
    wire [IW_DK-1:0] v_j;
    wire [IW_DM-1:0] v_k;
    wire v_mac_clear, v_mac_enable, v_write_enable;
    wire v_busy, v_done;

    loop_control #(.NI(N), .NJ(DK), .NK(DM), .JSTEP(1)) u_v (
        .clk(clk), .rst_n(rst_n), .start(v_start),
        .i(v_i), .j(v_j), .k(v_k),
        .mac_clear(v_mac_clear),
        .mac_enable(v_mac_enable),
        .write_enable(v_write_enable),
        .busy(v_busy), .done(v_done)
    );

    // u_o wires
    wire [IW_N-1:0] o_i;
    wire [IW_DK-1:0] o_j;
    wire [IW_N-1:0] o_k;
    wire o_mac_clear, o_mac_enable, o_write_enable;
    wire o_busy, o_done;

    loop_control #(.NI(N), .NJ(DK), .NK(N), .JSTEP(2)) u_o (
        .clk(clk), .rst_n(rst_n), .start(o_start),
        .i(o_i), .j(o_j), .k(o_k),
        .mac_clear(o_mac_clear),
        .mac_enable(o_mac_enable),
        .write_enable(o_write_enable),
        .busy(o_busy), .done(o_done)
    );
    
    //phase_qk wires
    wire [$clog2(N*DM)-1:0] qk_x_address = qk_i*DM + qk_k;
    wire [$clog2(DM*DK)-1:0] qk_wq_address = qk_k*DK + qk_j;
    wire [$clog2(DM*DK)-1:0] qk_wk_address = qk_k*DK + qk_j;
    wire [$clog2(N*DK)-1:0] qk_q_address = qk_i*DK + qk_j;
    wire [$clog2(N*DK)-1:0] qk_k_address = qk_i*DK + qk_j;

    //phase_sv wires
    wire [$clog2(N*DK)-1:0] s_q_address = s_i*DK + s_k;
    wire [$clog2(N*DK)-1:0] s_k_address = s_k + s_j*DK;
    wire [$clog2(N*N)-1:0] s_s_address = s_i*N + s_j;

    wire [$clog2(N*DM)-1:0] v_x_address = v_i*DM + v_k;
    wire [$clog2(DM*DK)-1:0] v_wv_address = v_k*DK + v_j;
    wire [$clog2(N*DK)-1:0] v_v_address = v_i*DK + v_j;

    //phase_o wires
    wire [$clog2(N*N)-1:0] o_a_address = o_i*N + o_k;
    wire [$clog2(N*DK)-1:0] o_v_address_0 = o_k*DK + o_j;
    wire [$clog2(N*DK)-1:0] o_o_address_0 = o_i*DK + o_j;
    wire [$clog2(N*DK)-1:0] o_v_address_1 = o_k*DK + o_j + 1;
    wire [$clog2(N*DK)-1:0] o_o_address_1 = o_i*DK + o_j + 1;

    // MUX for MAC operands
    // MUXing the operands on to the operand register of each MAC
    
    reg signed [17:0] mac0_a, mac1_a;
    reg signed [15:0] mac0_b, mac1_b;

    always @* begin
        mac0_a = 18'd0;
        mac0_b = 16'd0;
        mac1_a = 18'd0;
        mac1_b = 16'd0;

        case (state)
            ATTN_PH_QK: begin
                mac0_a = x_mem[qk_x_address];
                mac0_b = wq_mem[qk_wq_address];
                
                mac1_a = x_mem[qk_x_address];
                mac1_b = wk_mem[qk_wk_address];
            end

            ATTN_PH_SV: begin
                mac0_a = q_mem[s_q_address];
                mac0_b = k_mem[s_k_address];
                
                mac1_a = x_mem[v_x_address];
                mac1_b = wv_mem[v_wv_address];
            end

            ATTN_PH_O: begin
                mac0_a = a_mem[o_a_address];
                mac0_b = v_mem[o_v_address_0];
                
                mac1_a = a_mem[o_a_address];
                mac1_b = v_mem[o_v_address_1];
            end
            default: ;
        endcase
    end

    // MUX for MAC signals
    // MUXing the control signal on to the MACs
    
    reg mac0_enable, mac1_enable, mac0_clear, mac1_clear;

    always @* begin
        mac0_enable = 1'b0;
        mac0_clear = 1'b0;
        mac1_enable = 1'b0;
        mac1_clear = 1'b0;

        case (state)
            ATTN_PH_QK: begin
                mac0_enable = qk_mac_enable;
                mac0_clear = qk_mac_clear;
                
                mac1_enable = qk_mac_enable;
                mac1_clear = qk_mac_clear;
            end

            ATTN_PH_SV: begin
                mac0_enable = s_mac_enable;
                mac0_clear = s_mac_clear;
                
                mac1_enable = v_mac_enable;
                mac1_clear = v_mac_clear;
            end

            ATTN_PH_O: begin
                mac0_enable = o_mac_enable;
                mac0_clear = o_mac_clear;
                
                mac1_enable = o_mac_enable;
                mac1_clear = o_mac_clear;
            end
            default: ;
        endcase
    end

    // Two MACs

    wire signed [ACC_W-1:0] acc0, acc1;

    mac_unit #(.A_W(18), .B_W(16), .ACC_W(ACC_W)) u_mac0 (.clk(clk),
    .rst_n(rst_n), .clr(mac0_clear), .en(mac0_enable), .op_a(mac0_a), .op_b(mac0_b), .accumulator(acc0));

    mac_unit #(.A_W(18), .B_W(16), .ACC_W(ACC_W)) u_mac1 (.clk(clk),
    .rst_n(rst_n), .clr(mac1_clear), .en(mac1_enable), .op_a(mac1_a), .op_b(mac1_b), .accumulator(acc1));

    localparam SH_QK = FRAC;
    localparam SH_S  = FRAC + log4(DK);
    localparam SH_O  = 15;

    reg [4:0] shift0, shift1;

    always @* begin
        case (state)
            ATTN_PH_QK: begin shift0 = SH_QK; shift1 = SH_QK; end
            ATTN_PH_SV: begin shift0 = SH_S;  shift1 = SH_QK; end
            ATTN_PH_O:  begin shift0 = SH_O;  shift1 = SH_O;  end
            default:    begin shift0 = SH_QK; shift1 = SH_QK; end
        endcase
    end

    wire signed [ACC_W-1:0] ONE = {{(ACC_W-1){1'b0}}, 1'b1};

    wire signed [ACC_W-1:0] rnd0 = (acc0 + (ONE <<< (shift0-1))) >>> shift0;
    wire signed [ACC_W-1:0] rnd1 = (acc1 + (ONE <<< (shift1-1))) >>> shift1;

    wire signed [15:0] rounded0 = (rnd0 >  40'sd32767) ? 16'sh7FFF : (rnd0 < -40'sd32768) ? 16'sh8000 : rnd0[15:0];
    wire signed [15:0] rounded1 = (rnd1 >  40'sd32767) ? 16'sh7FFF : (rnd1 < -40'sd32768) ? 16'sh8000 : rnd1[15:0];

    wire [$clog2(N*N)-1:0] sm_s_read_address;
    wire signed [15:0] sm_s_read_data;
    wire [$clog2(N*N)-1:0] sm_a_write_address;
    wire signed [17:0] sm_a_write_data;
    wire sm_a_write_enable;
    wire sm_busy, sm_done;

    assign sm_s_read_data = s_mem[sm_s_read_address];

    softmax_unit #(.N(N), .LUT_FILE(LUT_FILE)) u_sm (.clk(clk), .rst_n(rst_n), .start(sm_start),
    .s_read_address(sm_s_read_address), .s_read_data(sm_s_read_data), .a_write_address(sm_a_write_address), 
    .a_write_data(sm_a_write_data), .a_write_enable(sm_a_write_enable), .busy(sm_busy), .done(sm_done));

    //write back
    always @(posedge clk) begin
        if (qk_write_enable) begin
            q_mem[qk_q_address] <= rounded0;
            k_mem[qk_k_address] <= rounded1;
        end
        if (s_write_enable) s_mem[s_s_address] <= rounded0;
        if (v_write_enable) v_mem[v_v_address] <= rounded1;
        if (o_write_enable) begin
            o_mem[o_o_address_0] <= rounded0;
            o_mem[o_o_address_1] <= rounded1;
        end
        if (sm_a_write_enable) a_mem[sm_a_write_address] <= sm_a_write_data;
    end

    // Phase_SV done 
    reg s_finished, v_finished;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_finished <= 1'b0;
            v_finished <= 1'b0;
        end else if (state == ATTN_IDLE && start) begin
            s_finished <= 1'b0;
            v_finished <= 1'b0;
        end else begin
            if (s_done) s_finished <= 1'b1;
            if (v_done) v_finished <= 1'b1;
        end
    end

    // phase start pulses
    assign qk_start = (state == ATTN_IDLE) && start;
    assign s_start  = (state == ATTN_PH_QK) && qk_done;
    assign v_start  = (state == ATTN_PH_QK) && qk_done;
    assign sm_start = (state == ATTN_PH_SV) && s_finished && v_finished;
    assign o_start  = (state == ATTN_PH_SM) && sm_done;

    // Main FSM
    always @(posedge clk) begin
        if(!rst_n) begin
            state <= ATTN_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cycles <= 32'd0;
        end
        else begin
            done <= 1'b0;
            if (busy) cycles <= cycles + 32'd1;

            case(state)
                ATTN_IDLE: if (start) begin
                    busy <= 1'b1;
                    cycles <= 32'd0;
                    state <= ATTN_PH_QK;
                end 

                ATTN_PH_QK: if(qk_done) state <= ATTN_PH_SV;

                ATTN_PH_SV: if(s_finished && v_finished) state <= ATTN_PH_SM;    

                ATTN_PH_SM: if(sm_done) state <= ATTN_PH_O;

                ATTN_PH_O: if(o_done) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ATTN_DONE;
                end

                ATTN_DONE: state <= ATTN_IDLE;
                default:;
            endcase
        end
    end
endmodule
