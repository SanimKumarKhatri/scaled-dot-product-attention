    module divider #(
        parameter WIDTH = 16
    )(
        input  wire clk,
        input  wire rst_n,
        input  wire start,
        input  wire [WIDTH-1:0] dividend,
        input  wire [WIDTH-1:0] divisor,
        output reg [WIDTH-1:0] quotient,
        output reg busy,
        output reg done
    );
        localparam [1:0]    IDLE = 2'd0,
                            RUN = 2'd1,
                            DONE = 2'd2;
        reg [1:0] state;

        localparam CNT_W = $clog2(WIDTH+1);

        reg [WIDTH-1:0] quotient_r;
        reg [WIDTH:0] remainder;
        reg [WIDTH-1:0] dividend_r;
        reg [WIDTH-1:0] divisor_r;
        reg [CNT_W-1:0] count;
        
        wire [WIDTH:0] rem_shifted = {remainder[WIDTH-1:0], dividend_r[WIDTH-1]};
        wire [WIDTH:0] rem_sub = rem_shifted - {1'b0, divisor_r};
        wire rem_neg = rem_sub[WIDTH];
        wire [WIDTH:0] rem_next = rem_neg ? rem_shifted : rem_sub;
        wire [WIDTH-1:0] quo_next = {quotient_r[WIDTH-2:0], ~rem_neg};

        always @(posedge clk) begin
            if (!rst_n) begin
                busy <= 1'b0;
                done <= 1'b0;
                quotient_r <= 0;
                remainder <= 0;
                dividend_r <= 0;
                divisor_r <= 0;
                count <= 0;
                state <= IDLE;
            end
            else begin
                done <= 1'b0;

                case(state)
                    IDLE: if (start) begin
                        dividend_r <= dividend;
                        divisor_r <= divisor;
                        quotient_r <= 0;
                        remainder <= 0;
                        count <= WIDTH;
                        busy <= 1'b1;
                        state <= RUN;
                    end

                    RUN:begin
                        if (count == 1) begin
                            quotient <= quo_next;
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= DONE;
                        end
                        else begin
                            remainder <= rem_next;
                            quotient_r <= quo_next;
                            dividend_r <= {dividend_r[WIDTH-2:0], 1'b0};
                            count <= count - 1;

                        end
                    end

                    DONE: state <= IDLE;
                    
                endcase
            end
        end
    endmodule
    