/*
Adder_CE #(
    .IMPL_TYPE ( IMPL_TYPE ),   string "DSP" / "LUT"
    .A_WIDTH   ( A_WIDTH   ),   
    .B_WIDTH   ( B_WIDTH   ),
    .A_TYPE    ( A_TYPE    ),   1: signed 0: unsigned
    .B_TYPE    ( B_TYPE    ),   1: signed 0: unsigned
    .OUT_WIDTH ( OUT_WIDTH ),   
    .LATENCY   ( LATENCY   ))
 u_Adder (
    .clk                     ( clk                  ),
    .A                       ( A    [A_WIDTH-1:0]   ),
    .B                       ( B    [B_WIDTH-1:0]   ),

    .SUM                     ( SUM  [OUT_WIDTH-1:0] )
);
*/
module Adder_CE #(
    parameter IMPL_TYPE = "LUT",
    parameter A_WIDTH = 16,
    parameter B_WIDTH = 16,
    parameter A_TYPE = 1,
    parameter B_TYPE = 1, 
    parameter OUT_WIDTH = 32,
    parameter LATENCY = 4
) (
    input wire clk,
    input wire clock_enable,
    input wire [A_WIDTH-1:0] A,
    input wire [B_WIDTH-1:0] B,
    output wire signed [OUT_WIDTH-1:0] SUM
);

localparam A_WIDTH_E = (A_TYPE == 1)? A_WIDTH : (A_WIDTH + 1);
localparam B_WIDTH_E = (B_TYPE == 1)? B_WIDTH : (B_WIDTH + 1);
wire signed [A_WIDTH_E-1:0] A_E;
wire signed [B_WIDTH_E-1:0] B_E;
localparam WIDTH_E = (A_WIDTH_E > B_WIDTH_E)? A_WIDTH_E : B_WIDTH_E;

generate
    if(A_TYPE == 0) begin
        assign A_E = {1'b0, A};
    end else begin
        assign A_E = A;
    end
    if(B_TYPE == 0) begin
        assign B_E = {1'b0, B};
    end else begin
        assign B_E = B;
    end
endgenerate

reg signed [WIDTH_E-1:0] A_G;
reg signed [WIDTH_E-1:0] B_G;
generate
    if(LATENCY >= 2) begin
        always @(posedge clk ) begin
            if(clock_enable) begin
                A_G <= {{WIDTH_E-A_WIDTH_E{A_E[A_WIDTH_E-1]}}, A_E};
                B_G <= {{WIDTH_E-B_WIDTH_E{B_E[B_WIDTH_E-1]}}, B_E};
            end
        end
    end else begin
        always @(*) begin
            A_G = {{WIDTH_E-A_WIDTH_E{A_E[A_WIDTH_E-1]}}, A_E};
            B_G = {{WIDTH_E-B_WIDTH_E{B_E[B_WIDTH_E-1]}}, B_E};
        end
    end  
endgenerate

wire signed [OUT_WIDTH-1:0] SUM_G;
generate
    if(IMPL_TYPE == "DSP") begin
        Adder_DSP_CE #(
            .WIDTH_E   ( WIDTH_E   ),
            .OUT_WIDTH ( OUT_WIDTH ),
            .LATENCY   ( LATENCY   ))
        u_Adder_DSP (
            .clk                     ( clk                  ),
            .clock_enable            ( clock_enable         ),
            .A_G                     ( A_G    [WIDTH_E-1:0] ),
            .B_G                     ( B_G    [WIDTH_E-1:0] ),

            .SUM_G                   ( SUM_G  [OUT_WIDTH-1:0]   )
        );
    end else begin
        Adder_LUT_CE #(
            .WIDTH_E   ( WIDTH_E   ),
            .OUT_WIDTH ( OUT_WIDTH ),
            .LATENCY   ( LATENCY   ))
        u_Adder_LUT (
            .clk                     ( clk                  ),
            .clock_enable            ( clock_enable         ),
            .A_G                     ( A_G    [WIDTH_E-1:0] ),
            .B_G                     ( B_G    [WIDTH_E-1:0] ),

            .SUM_G                   ( SUM_G  [OUT_WIDTH-1:0]   )
        );
    end
endgenerate
assign SUM = SUM_G;
endmodule



module Adder_LUT_CE #(
    parameter WIDTH_E = 66,
    parameter OUT_WIDTH = 66,
    parameter LATENCY = 2
) (
    input wire clk,
    input wire clock_enable,
    input wire signed [WIDTH_E-1:0] A_G,
    input wire signed [WIDTH_E-1:0] B_G,
    output wire signed [OUT_WIDTH-1:0] SUM_G
);
integer s;
reg signed [WIDTH_E:0] SUM_reg [LATENCY-2:0];
generate
    if(LATENCY >= 1) begin
        always @(posedge clk ) begin
            if(clock_enable) begin
                SUM_reg[0] <= A_G + B_G;
            end
        end
    end else begin
        always @(*) begin
            SUM_reg[0] = A_G + B_G;
        end
    end
endgenerate

generate
    if(LATENCY > 2) begin
        always @(posedge clk ) begin
            if(clock_enable) begin
                for(s = 0; s < LATENCY - 2; s = s + 1) begin
                    SUM_reg[s + 1] <= SUM_reg[s];
                end
            end
        end
        assign SUM_G = SUM_reg[LATENCY-2][OUT_WIDTH-1:0];
    end else begin
        assign SUM_G = SUM_reg[0];
    end
endgenerate
endmodule

(* use_dsp = "yes" *)module Adder_DSP_CE #(
    parameter WIDTH_E = 66,
    parameter OUT_WIDTH = 66,
    parameter LATENCY = 2
) (
    input wire clk,
    input wire clock_enable,
    input wire signed [WIDTH_E-1:0] A_G,
    input wire signed [WIDTH_E-1:0] B_G,
    output wire signed [OUT_WIDTH-1:0] SUM_G
);

integer s;
reg signed [WIDTH_E:0] SUM_reg [LATENCY-2:0];
generate
    if(LATENCY >= 1) begin
        always @(posedge clk ) begin
            if(clock_enable) begin
                SUM_reg[0] <= A_G + B_G;
            end
        end
    end else begin
        always @(*) begin
            SUM_reg[0] = A_G + B_G;
        end
    end
endgenerate

generate
    if(LATENCY > 2) begin
        always @(posedge clk ) begin
            if(clock_enable) begin
                for(s = 0; s < LATENCY - 2; s = s + 1) begin
                    SUM_reg[s + 1] <= SUM_reg[s];
                end
            end
        end
        assign SUM_G = SUM_reg[LATENCY-2][OUT_WIDTH-1:0];
    end else begin
        assign SUM_G = SUM_reg[0];
    end
endgenerate
endmodule











