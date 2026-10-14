// loop control

module loop_ctrl #(
    parameter NI = 2,
    parameter NJ = 4,
    parameter NK = 4,
    parameter JSTEP = 1
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    output reg [((NI>1) ? $clog2(NI) : 1)-1:0] i,
    output reg [((NJ>1) ? $clog2(NJ) : 1)-1:0] j,
    output reg [((NK>1) ? $clog2(NK) : 1)-1:0] k,

    output wire mac_clear,
    output wire mac_enable,
    output wire write_enable,

    output reg busy,
    output reg done
);
    // loop states
    localparam [1:0]    IDLE = 2'd0,
                        MAC = 2'd1,
                        WRITE = 2'd2,
                        FINISHED = 2'd3;
    
    reg [1:0] state;

    // assigning output wires
    assign mac_clear = (state == IDLE && start) || (state == WRITE);
    assign mac_enable = (state == MAC);
    assign write_enable = (state == WRITE);

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            i <= 0; j <= 0; k <= 0;
            state <= IDLE;
        end
        else begin
            done <= 1'b0;
            
            case(state) 
                IDLE: if (start) begin
                        i <= 0; j <= 0; k <= 0;
                        state <= MAC;
                        busy <= 1'b1;
                    end

                MAC: begin
                    if (k == (NK -1)) state <= WRITE;
                    else k <= k + 1;
                end

                WRITE: begin
                    k <= 0;
                    if (j == (NJ - JSTEP)) begin
                        j <= 0;
                        if (i == (NI - 1)) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= FINISHED;
                        end
                        else begin
                            i <= i + 1;
                            state <= MAC;
                        end
                    end
                    else begin
                        j <= j + JSTEP;
                        state <= MAC;
                    end
                end

                FINISHED: state <= IDLE;
            endcase
        end
    end

endmodule