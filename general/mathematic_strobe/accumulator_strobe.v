/*
    意图: 针对strobe之间有间隔的累加
*/
module accumulator_strobe #(
    parameter DATA_IN_WIDTH = 16,
    parameter DATA_OUT_WIDTH = 20,
    parameter IMPL_TYPE = "DSP",
    parameter DATA_TYPE = 1,
    parameter ADDER_LATENCY = 2
) (
    input wire clk,
    input wire in_strobe,
    input wire clear,
    input wire [DATA_IN_WIDTH-1:0] data_in,
    output reg data_out_strobe,
    output reg [DATA_OUT_WIDTH-1:0] data_out
);



// 加法器变量
wire [DATA_OUT_WIDTH-1:0] adder_out;
wire adder_out_strobe;

// 临时存储变量
reg adder_in_strobe;
reg [DATA_IN_WIDTH-1:0] adder_in;
reg [DATA_OUT_WIDTH-1:0] temp_accu;
always @(posedge clk ) begin
    if(clear) begin
        temp_accu <= 0;
        adder_in_strobe <= 0;
        adder_in <= 0;
    end else if(in_strobe) begin
        temp_accu <= data_in;
        adder_in_strobe <= in_strobe;
    end
end


Adder_strobe #(
    .IMPL_TYPE ( IMPL_TYPE          ),  
    .A_WIDTH   ( DATA_IN_WIDTH      ),   
    .B_WIDTH   ( DATA_OUT_WIDTH     ),
    .A_TYPE    ( DATA_TYPE          ),   
    .B_TYPE    ( DATA_TYPE          ),   
    .OUT_WIDTH ( DATA_OUT_WIDTH     ),   
    .LATENCY   ( ADDER_LATENCY      ))
 u_Adder_sample_i (
    .clk                     ( clk                  ),
    .data_in_strobe          ( in_strobe            ),
    .A                       ( data_in              ),
    .B                       ( temp_accu            ),

    .data_out_strobe         ( adder_out_strobe     ),
    .SUM                     ( adder_out            )
);
endmodule