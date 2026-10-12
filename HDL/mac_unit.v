// MAC (Multiply-Accumulate) Unit
//  acc <- 0            when reset is low
//  acc <- 0            when clear is high
//  acc <- acc + a*b    when enable is high
//  acc <- acc          holds otherwise

module mac #(
    parameter A_W  = 16,      // width of operand a
    parameter B_W  = 16,      // width of operand b
    parameter ACC_W  = 40      // width of accumulator
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clr,
    input  wire en,
    input  wire signed [A_W-1:0] op_a,
    input  wire signed [B_W-1:0] op_b,
    output reg signed [ACC_W-1:0] accumulator
);
    wire signed [A_W+B_W-1:0]product = op_a*op_b;
    always @(posedge clk) begin
        if(!rst_n) accumulator <= {ACC_W{1'b0}};
        else if (clr) accumulator <= {ACC_W{1'b0}};
        else if (en) accumulator <= accumulator + product;
    end
endmodule