`timescale 1ns / 1ps
// reviewed by tony
// 一共 5(adder2 + multiplier3)个 clk 延时


// strobe 型平方和模块。
// 数据通路连续运行，in_strobe 只用于标记哪一拍输入有效。
// square_sum = i*i + q*q，out_strobe 与 square_sum 同拍有效。
module square_sum_strobe #(
    parameter DATA_WIDTH = 16
) (
    input  wire                     clk,
    input  wire                     in_strobe,
    input  wire [DATA_WIDTH-1:0]    i,
    input  wire [DATA_WIDTH-1:0]    q,

    output wire [2*DATA_WIDTH-1:0]  square_sum,
    output wire                     out_strobe
);

    localparam ARITH_IMPL_TYPE = "LUT";
    localparam DELAY_IMPL_TYPE = 0;

    localparam integer MULT_LATENCY       = 3;
    localparam integer ADDER_LATENCY      = 2;
    localparam integer SQUARE_SUM_LATENCY = MULT_LATENCY + ADDER_LATENCY;
    localparam integer PRODUCT_WIDTH      = 2 * DATA_WIDTH - 1;
    localparam integer SUM_WIDTH          = PRODUCT_WIDTH + 1;

    wire [PRODUCT_WIDTH-1:0] i_square;
    wire [PRODUCT_WIDTH-1:0] q_square;

    // 该 multiplier 带来 MULT_LATENCY 个 fabric clk 延时。
    multiplier #(
        .IMPL_TYPE (  ARITH_IMPL_TYPE    ),     // 实现类型
        .A_WIDTH   ( DATA_WIDTH    ),
        .B_WIDTH   ( DATA_WIDTH    ),
        .A_TYPE    ( 1             ),
        .B_TYPE    ( 1             ),
        .LATENCY   ( MULT_LATENCY  ),
        .OUT_WIDTH ( PRODUCT_WIDTH ))
    u_i_square (
        .clk ( clk      ),
        .A   ( i        ),
        .B   ( i        ),
        .P   ( i_square )
    );

    // 该 multiplier 带来 MULT_LATENCY 个 fabric clk 延时。
    multiplier #(
        .IMPL_TYPE (  ARITH_IMPL_TYPE     ),     // 实现类型
        .A_WIDTH   ( DATA_WIDTH    ),
        .B_WIDTH   ( DATA_WIDTH    ),
        .A_TYPE    ( 1             ),
        .B_TYPE    ( 1             ),
        .LATENCY   ( MULT_LATENCY  ),
        .OUT_WIDTH ( PRODUCT_WIDTH ))
    u_q_square (
        .clk ( clk      ),
        .A   ( q        ),
        .B   ( q        ),
        .P   ( q_square )
    );

    // 该 Adder 带来 ADDER_LATENCY 个 fabric clk 延时。
    Adder #(
        .IMPL_TYPE ( ARITH_IMPL_TYPE ),
        .A_WIDTH   ( PRODUCT_WIDTH   ),
        .B_WIDTH   ( PRODUCT_WIDTH   ),
        .A_TYPE    ( 0               ),
        .B_TYPE    ( 0               ),
        .OUT_WIDTH ( SUM_WIDTH       ),
        .LATENCY   ( ADDER_LATENCY   ))
    u_square_sum_adder (
        .clk ( clk        ),
        .A   ( i_square   ),
        .B   ( q_square   ),
        .SUM ( square_sum )
    );

    // 该 delay 带来 SQUARE_SUM_LATENCY 个 fabric clk 延时，对齐平方和输出。
    delay #(
        .DATA_WIDTH ( 1                  ),
        .DELAY_CLK  ( SQUARE_SUM_LATENCY ),
        .IMPL_TYPE  ( DELAY_IMPL_TYPE    ))
    u_delay_out_strobe (
        .clk      ( clk             ),
        .data_in  ( in_strobe       ),
        .data_out ( out_strobe      )
    );

endmodule
