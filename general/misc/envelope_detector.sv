`timescale 1ns / 1ps


module envelope_detector #(
    parameter BIT_ENVELOPE_DETECTION = 32,
    parameter DETECTION_CLOCK_NUM = 16,
    parameter DETECTION_HIGH_NUM = 12,
    parameter CHANNEL_NUM = 8
)(
input wire clk,
input wire rst_n,
input wire [32*CHANNEL_NUM-1:0] signal_in,  // 输入信号
input wire [BIT_ENVELOPE_DETECTION-1:0] envelope_detection0,
input wire [BIT_ENVELOPE_DETECTION-1:0] envelope_detection1,

output reg envelope,
output wire [32*CHANNEL_NUM-1:0] signal_out // 和脉冲对齐
    );

// 平方和 5个延迟
wire [15:0] i;
wire [30:0] i2;
wire [15:0] q;
wire [30:0] q2;
assign q = signal_in[31:16];
assign i = signal_in[15:0];

multiplier #(
    .A_WIDTH   ( 16   ),     // a输入位宽
    .B_WIDTH   ( 16   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3   ),     // 总延迟
    .OUT_WIDTH ( 31 ))     // 输出位宽,取低位
 u_multiplier_i2 (
    .clk                     ( clk                  ),
    .A                       ( i   ),
    .B                       ( i   ),

    .P                       ( i2 )
); multiplier #(
    .A_WIDTH   ( 16   ),     // a输入位宽
    .B_WIDTH   ( 16   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3   ),     // 总延迟
    .OUT_WIDTH ( 31 ))     // 输出位宽,取低位
 u_multiplier_q2 (
    .clk                     ( clk                  ),
    .A                       ( q   ),
    .B                       ( q   ),

    .P                       ( q2 )
);

wire [31:0] square_sum;
Adder #(
    .IMPL_TYPE ( "DSP" ),   
    .A_WIDTH   ( 31   ),   
    .B_WIDTH   ( 31   ),
    .A_TYPE    ( 0    ),   
    .B_TYPE    ( 0    ),   
    .OUT_WIDTH ( 32 ),   
    .LATENCY   ( 2   ))
 u_Adder (
    .clk                     ( clk                  ),
    .A                       ( i2       ),
    .B                       ( q2       ),

    .SUM                     ( square_sum )
);


// 滑动窗口1个延迟
reg [DETECTION_CLOCK_NUM-1:0] high_window = 0;
reg [DETECTION_CLOCK_NUM-1:0] low_window = 0;
always @(posedge clk ) begin
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
    .in_advance         ( 1'b1  ),
    .in_addends         ( high_cnt_in  ),

    .out_sum            ( out_sum_high     )
);UnsignedAdderTreePipelined #(
    .DATA_WIDTH   ( 1   ),
    .LENGTH       ( DETECTION_CLOCK_NUM       )
    )
 u_low_cnt (
    .clk                ( clk         ),
    .reset              ( 1'b0       ),
    .in_advance         ( 1'b1  ),
    .in_addends         ( low_cnt_in  ),

    .out_sum            ( out_sum_low     )
);

// DETECTION_HIGH_NUM + 1个延时
wire envelope_pos_pre;
always @(posedge clk ) begin
    if(!rst_n) begin
        envelope <= 0;
    end else if(out_sum_high >= DETECTION_HIGH_NUM) begin
        envelope <= 1;
    end else if(out_sum_low >= DETECTION_HIGH_NUM) begin
        envelope <= 0;
    end else begin
        envelope <= envelope;
    end
end

delay #(
    .DATA_WIDTH ( 32*CHANNEL_NUM ),
    .DELAY_CLK  ( DETECTION_HIGH_NUM + 1 + $clog2(DETECTION_CLOCK_NUM) + 1 + 5 ),
    .IMPL_TYPE  ( 0  )) // fifo
 u_delay (
    .clk                     ( clk                        ),
    .data_in                 ( signal_in    ),

    .data_out                ( signal_out   )
);

endmodule
