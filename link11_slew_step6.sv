module link11_slew_step6 #(
    parameter EQ_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 5
) (
    input wire clk,
    input wire rst_n,
    input wire [EQ_WIDTH-1:0] equalized_i, equalized_q,   
    input wire equalized_strobe,
    input wire equalized_start,
    
    output wire [1:0] dibit,
    output wire dibit_strobe
);
    
    // 1.取采样点, 求一个窗口内的平均, 需要start信号来对齐
    wire sample_strobe;
    wire [EQ_WIDTH-1:0] sample_i, sample_q;

    assign sample_strobe = equalized_strobe;
    assign sample_i = equalized_i;
    assign sample_q = equalized_q;
    

    // 2.本地模拟加扰器, 生成加扰信号
    wire out_strobe;
    wire [15:0] out_i, out_q;
    link11_slew_step6_scrambler #(
        .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
    u_link11_slew_step6_scrambler (
        .clk                     ( clk                ),
        .rst_n                   ( rst_n              ),
        .start                   ( equalized_start    ),
        .strobe                  ( sample_strobe      ),

        .out_strobe              ( out_strobe         ),
        .out_i                   ( out_i       [15:0] ),
        .out_q                   ( out_q       [15:0] )
    );


    // 3.对采样信号进行反加扰旋转
    localparam MIXER_OUT_WIDTH = EQ_WIDTH + 16;
    wire [MIXER_OUT_WIDTH-1:0] mixer_i, mixer_q;
    mixer_strobe #(
        .A_DATA_WIDTH ( EQ_WIDTH    ),
        .B_DATA_WIDTH ( 16          ),
        .IMPL_TYPE    ( "LUT"       ),
        .MODE         ( 0           ))
    u_mixer_strobe (
        .clk                     ( clk                  ),
        .rst_n                   ( rst_n                ),
        .in_strobe               ( out_strobe           ),
        .ai                      ( sample_i             ),
        .aq                      ( sample_q             ),
        .bi                      ( out_i                ),
        .bq                      ( out_q                ),

        .out_strobe              ( mixer_strobe         ),
        .oi                      ( mixer_i              ),
        .oq                      ( mixer_q              )
    );

    // 4.QPSK解调通用模块, 自带gray码映射, 对应一个symbol
    qpsk_decoder #(
        .DATA_WIDTH ( MIXER_OUT_WIDTH ))
    u_qpsk_decoder (
        .clk                     ( clk              ),
        .strobe                  ( mixer_strobe     ),
        .i                       ( mixer_i          ),
        .q                       ( mixer_q          ),

        .decode_out              ( dibit            ),
        .decode_strobe           ( dibit_strobe     )
    );

endmodule