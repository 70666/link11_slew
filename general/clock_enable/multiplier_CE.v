/*
multiplier_CE #(
    .A_WIDTH   ( A_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( B_WIDTH   ),     // b输入位宽
    .A_TYPE    ( A_TYPE    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( B_TYPE    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( LATENCY   ),     // 总延迟
    .OUT_WIDTH ( OUT_WIDTH ))     // 输出位宽,取低位
 u_multiplier (
    .clk                     ( clk                  ),
    .A                       ( A    [A_WIDTH-1:0]   ),
    .B                       ( B    [B_WIDTH-1:0]   ),

    .P                       ( P    [OUT_WIDTH-1:0] )
);
*/
module multiplier_CE #(
    parameter A_WIDTH = 16,     // a输入位宽
    parameter B_WIDTH = 16,     // b输入位宽
    parameter A_TYPE  = 1,      // 1:有符号数 0:无符号数
    parameter B_TYPE  = 1,
    parameter LATENCY = 4,      //
    parameter OUT_WIDTH = 32    // 输出位宽,取低位
) (
    input wire clk,
    input wire clock_enable,
    input wire [A_WIDTH-1:0] A,
    input wire [B_WIDTH-1:0] B,
    output wire [OUT_WIDTH-1:0] P
);

// width extension
localparam A_WIDTH_E = (A_TYPE == 1)? A_WIDTH : (A_WIDTH + 1);
localparam B_WIDTH_E = (B_TYPE == 1)? B_WIDTH : (B_WIDTH + 1);
wire signed [A_WIDTH_E-1:0] A_E;
wire signed [B_WIDTH_E-1:0] B_E;
reg signed [A_WIDTH_E-1:0] A_reg;
reg signed [B_WIDTH_E-1:0] B_reg;
generate
    if(A_TYPE == 1) begin
        assign A_E = A[A_WIDTH-1:0];  
    end else begin
        assign A_E = {1'b0, A[A_WIDTH-1:0]};
    end
    if(B_TYPE == 1) begin
        assign B_E = B[B_WIDTH-1:0];
    end else begin
        assign B_E = {1'b0, B[B_WIDTH-1:0]};
    end
endgenerate

// in reg
always @(posedge clk ) begin
    if(clock_enable) begin
        A_reg <= A_E;
        B_reg <= B_E;
    end
end

integer i;
reg signed [A_WIDTH_E + B_WIDTH_E-1:0] P_reg [LATENCY - 2 : 0];
    always @(posedge clk ) begin
        if(clock_enable) begin
            if(LATENCY >= 2)
                P_reg[0] <= A_reg * B_reg;
            else
                P_reg[0] <= A_E * B_E;
            for(i = 0; i < LATENCY - 2; i = i + 1) begin
                P_reg[i+1] <= P_reg[i];
            end
        end
    end
generate
    if(LATENCY >= 2)
        assign P = P_reg[LATENCY-2][OUT_WIDTH-1:0];
    else
        assign P = P_reg[0][OUT_WIDTH-1:0];
endgenerate

endmodule
