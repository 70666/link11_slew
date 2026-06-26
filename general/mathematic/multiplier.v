/*
multiplier #(
    .IMPL_TYPE (  "DSP"    ),     // 实现类型
    .A_WIDTH   ( A_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( B_WIDTH   ),     // b输入位宽
    .A_TYPE    ( A_TYPE    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( B_TYPE    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( LATENCY   ),     // 总延迟, 必须大于0
    .OUT_WIDTH ( OUT_WIDTH ))     // 输出位宽,取低位
 u_multiplier (
    .clk                     ( clk                  ),
    .A                       ( A    [A_WIDTH-1:0]   ),
    .B                       ( B    [B_WIDTH-1:0]   ),

    .P                       ( P    [OUT_WIDTH-1:0] )
);
*/
module multiplier #(
    parameter IMPL_TYPE = "DSP",// 实现类型
    parameter A_WIDTH = 16,     // a输入位宽
    parameter B_WIDTH = 16,     // b输入位宽
    parameter A_TYPE  = 1,      // 1:有符号数 0:无符号数
    parameter B_TYPE  = 1,
    parameter LATENCY = 4,      //
    parameter OUT_WIDTH = 32    // 输出位宽,取低位
) (
    input wire clk,
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
generate
    if(LATENCY >= 2) begin              // 如果大于等于2 就有输入寄存器
        always @(posedge clk ) begin
            A_reg <= A_E;
            B_reg <= B_E;
        end
    end else begin                      // 否则组合逻辑实现
        always @( * ) begin
            A_reg = A_E;
            B_reg = B_E;
        end
    end
endgenerate

wire [OUT_WIDTH-1:0] P_G;
assign P = P_G;
generate
    if(IMPL_TYPE == "DSP") begin
        multiplier_dsp #(
            .A_WIDTH_E ( A_WIDTH_E ),
            .B_WIDTH_E ( B_WIDTH_E ),
            .LATENCY   ( LATENCY   ),
            .OUT_WIDTH ( OUT_WIDTH ))
        u_multiplier_dsp (
            .clk                     ( clk                    ),
            .A_reg                   ( A_reg  [A_WIDTH_E-1:0] ),
            .B_reg                   ( B_reg  [B_WIDTH_E-1:0] ),

            .P_G                     ( P_G    [OUT_WIDTH-1:0] )
        );
    end else begin
        multiplier_lut #(
            .A_WIDTH_E ( A_WIDTH_E ),
            .B_WIDTH_E ( B_WIDTH_E ),
            .LATENCY   ( LATENCY   ),
            .OUT_WIDTH ( OUT_WIDTH ))
        u_multiplier_lut (
            .clk                     ( clk                    ),
            .A_reg                   ( A_reg  [A_WIDTH_E-1:0] ),
            .B_reg                   ( B_reg  [B_WIDTH_E-1:0] ),

            .P_G                     ( P_G    [OUT_WIDTH-1:0] )
        );
    end
endgenerate

endmodule

(* use_dsp = "yes" *)module multiplier_dsp #(
    parameter A_WIDTH_E = 16,
    parameter B_WIDTH_E = 16,
    parameter LATENCY = 2,
    parameter OUT_WIDTH = 32
) (
    input wire clk,
    input wire signed [A_WIDTH_E-1:0] A_reg,
    input wire signed [B_WIDTH_E-1:0] B_reg,
    output wire signed [OUT_WIDTH-1:0] P_G
);

reg signed [A_WIDTH_E + B_WIDTH_E-1:0] P_reg [LATENCY - 2 : 0];
integer s;

generate
    if(LATENCY > 2) begin
        always @(posedge clk ) begin
            P_reg[0] <= A_reg * B_reg;
            for(s = 0; s < LATENCY - 2; s = s + 1) begin
                P_reg[s + 1] <= P_reg[s];
            end
        end
        assign P_G = P_reg[LATENCY-2];
    end else begin
        always @(posedge clk ) begin
            P_reg[0] <= A_reg * B_reg;
        end
        assign P_G = P_reg[0];
    end
endgenerate

endmodule


(* use_dsp = "no" *)module multiplier_lut #(
    parameter A_WIDTH_E = 16,
    parameter B_WIDTH_E = 16,
    parameter LATENCY = 2,
    parameter OUT_WIDTH = 32
) (
    input wire clk,
    input wire signed [A_WIDTH_E-1:0] A_reg,
    input wire signed [B_WIDTH_E-1:0] B_reg,
    output wire signed [OUT_WIDTH-1:0] P_G
);

reg signed [A_WIDTH_E + B_WIDTH_E-1:0] P_reg [LATENCY - 2 : 0];
integer s;

generate
    if(LATENCY > 2) begin
        always @(posedge clk ) begin
            P_reg[0] <= A_reg * B_reg;
            for(s = 0; s < LATENCY - 2; s = s + 1) begin
                P_reg[s + 1] <= P_reg[s];
            end
        end
        assign P_G = P_reg[LATENCY-2];
    end else begin
        always @(posedge clk ) begin
            P_reg[0] <= A_reg * B_reg;
        end
        assign P_G = P_reg[0];
    end
endgenerate

endmodule