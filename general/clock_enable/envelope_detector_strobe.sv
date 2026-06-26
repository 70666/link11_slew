`timescale 1ns / 1ps

module envelope_detector_strobe #(
    parameter DATA_WIDTH = 16,
    parameter BIT_ENVELOPE_DETECTION = 32,
    parameter DETECTION_CLOCK_NUM = 16,
    parameter DETECTION_HIGH_NUM = 12,
    parameter CHANNEL_NUM = 8
)(
input wire clk,
input wire clock_enable,
input wire rst_n,
input wire [CHANNEL_NUM*2*DATA_WIDTH-1:0] signal_in,  // 输入信号
input wire [BIT_ENVELOPE_DETECTION-1:0] envelope_detection0,
input wire [BIT_ENVELOPE_DETECTION-1:0] envelope_detection1,

output reg envelope,
output reg clock_enable_out,
output wire [CHANNEL_NUM*2*DATA_WIDTH-1:0] signal_out // 和脉冲对齐
    );

// 平方和 5个延迟
wire [DATA_WIDTH-1:0] i;
wire [2*DATA_WIDTH-2:0] i2;
wire [DATA_WIDTH-1:0] q;
wire [2*DATA_WIDTH-2:0] q2;
assign q = signal_in[2*DATA_WIDTH-1:DATA_WIDTH];
assign i = signal_in[DATA_WIDTH-1:0];
multiplier_CE #(
    .A_WIDTH   ( DATA_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( DATA_WIDTH   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3   ),     // 总延迟
    .OUT_WIDTH ( 2*DATA_WIDTH-1 ))     // 输出位宽,取低位
 u_multiplier_i2 (
    .clk                     ( clk                  ),
    .clock_enable            ( clock_enable         ),
    .A                       ( i   ),
    .B                       ( i   ),

    .P                       ( i2 )
); multiplier_CE #(
    .A_WIDTH   ( DATA_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( DATA_WIDTH   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3   ),     // 总延迟
    .OUT_WIDTH ( 2*DATA_WIDTH-1 ))     // 输出位宽,取低位
 u_multiplier_q2 (
    .clk                     ( clk                  ),
    .clock_enable            ( clock_enable         ),
    .A                       ( q   ),
    .B                       ( q   ),

    .P                       ( q2 )
);
wire [31:0] square_sum;
Adder_CE #(
    .IMPL_TYPE ( "DSP" ),   
    .A_WIDTH   ( 2*DATA_WIDTH-1   ),   
    .B_WIDTH   ( 2*DATA_WIDTH-1   ),
    .A_TYPE    ( 0    ),   
    .B_TYPE    ( 0    ),   
    .OUT_WIDTH ( 2*DATA_WIDTH ),   
    .LATENCY   ( 2   ))
 u_Adder (
    .clk                     ( clk                  ),
    .clock_enable            ( clock_enable         ),
    .A                       ( i2       ),
    .B                       ( q2       ),

    .SUM                     ( square_sum )
);
// 滑动窗口1个延迟
reg [DETECTION_CLOCK_NUM-1:0] high_window = 0;
reg [DETECTION_CLOCK_NUM-1:0] low_window = 0;
always @(posedge clk ) begin
    if(clock_enable) begin
        if(square_sum > envelope_detection1) begin
            high_window <= {high_window[DETECTION_CLOCK_NUM-2:0], 1'b1};
        end else begin
            high_window <= {high_window[DETECTION_CLOCK_NUM-2:0], 1'b0};
        end
        if(square_sum > envelope_detection0) begin
            low_window <= {low_window[DETECTION_CLOCK_NUM-2:0], 1'b0};
        end else begin
            low_window <= {low_window[DETECTION_CLOCK_NUM-2:0], 1'b1};
        end
    end
end
wire high_cnt_in [DETECTION_CLOCK_NUM-1:0];
wire low_cnt_in [DETECTION_CLOCK_NUM-1:0];
genvar s;
generate
    for(s = 0; s < DETECTION_CLOCK_NUM; s = s + 1) begin
        assign high_cnt_in[s] = high_window[s];
        assign low_cnt_in[s] = low_window[s];
    end
endgenerate

// $clog2(DETECTION_CLOCK_NUM) 个延迟
wire [$clog2(DETECTION_CLOCK_NUM):0] out_sum_high;
wire [$clog2(DETECTION_CLOCK_NUM):0] out_sum_low;
UnsignedAdderTreePipelined #(
    .DATA_WIDTH   ( 1   ),
    .LENGTH       ( DETECTION_CLOCK_NUM       )
    )
 u_high_cnt (
    .clk                ( clk         ),
    .reset              ( 1'b0       ),
    .in_advance         ( clock_enable  ),
    .in_addends         ( high_cnt_in  ),

    .out_sum            ( out_sum_high     )
);UnsignedAdderTreePipelined #(
    .DATA_WIDTH   ( 1   ),
    .LENGTH       ( DETECTION_CLOCK_NUM       )
    )
 u_low_cnt (
    .clk                ( clk         ),
    .reset              ( 1'b0       ),
    .in_advance         ( clock_enable  ),
    .in_addends         ( low_cnt_in  ),

    .out_sum            ( out_sum_low     )
);
// DETECTION_HIGH_NUM + 1个延时
wire envelope_pos_pre;
always @(posedge clk ) begin
    if(!rst_n) begin
        envelope <= 0;
    end else if(clock_enable) begin
        if(out_sum_high >= DETECTION_HIGH_NUM) begin
            envelope <= 1;
        end else if(out_sum_low >= DETECTION_HIGH_NUM) begin
            envelope <= 0;
        end
    end
end
delay_CE #(
    .DATA_WIDTH ( CHANNEL_NUM*2*DATA_WIDTH ),
    .DELAY_CLK  ( DETECTION_HIGH_NUM + $clog2(DETECTION_CLOCK_NUM) + 7 ),
    .IMPL_TYPE  ( 0  )) // fifo
 u_delay (
    .clk                     ( clk                        ),
    .clock_enable            ( clock_enable               ),
    .data_in                 ( signal_in    ),

    .data_out                ( signal_out   )
);
always @(posedge clk ) begin
    if(clock_enable) begin
        clock_enable_out <= 1'b1;
    end else begin
        clock_enable_out <= 1'b0;
    end
end
endmodule
