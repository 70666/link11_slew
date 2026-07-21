module link11_slew_step6_8psk_demod #(
    parameter EQ_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 5
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [EQ_WIDTH+15:0] mixer_mag_thres,
    input wire [EQ_WIDTH-1:0] equalized_i, equalized_q,   
    input wire equalized_strobe,
    input wire equalized_start,
    output wire [1:0] dibit,
    output wire dibit_strobe,
    output reg mixer_mag_envelope
);
    
    // 1.取采样点, 求一个窗口内的平均, 需要start信号来对齐
    wire sample_strobe;
    wire [EQ_WIDTH-1:0] sample_i, sample_q;
    link11_slew_step6_sample #(
        .WINDOW_NUM ( WINDOW_NUM ),
        .EQ_WIDTH   ( EQ_WIDTH   ))
    u_link11_slew_step6_sample (
        .clk                     ( clk                              ),
        .rst_n                   ( rst_n                            ),
        .equalized_i             ( equalized_i       [EQ_WIDTH-1:0] ),
        .equalized_q             ( equalized_q       [EQ_WIDTH-1:0] ),
        .equalized_strobe        ( equalized_strobe                 ),
        .equalized_start         ( equalized_start                  ),
        .demod_done              ( demod_done                       ),

        .sample_strobe           ( sample_strobe                    ),
        .sample_i                ( sample_i          [EQ_WIDTH-1:0] ),
        .sample_q                ( sample_q          [EQ_WIDTH-1:0] )
    );

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
        .demod_done              ( demod_done         ),

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

    // 5.平方和用来保底检测信号结束
    wire [MIXER_OUT_WIDTH-1:0] mag_mixer;
    complex_to_mag #(
        .DATA_WIDTH ( MIXER_OUT_WIDTH ))
    u_complex_to_mag (
        .clk                     ( clk              ),
        .enable                  ( 1'b1             ),
        .reset                   ( 1'b0             ),
        .i                       ( mixer_i          ),
        .q                       ( mixer_q          ),
        .input_strobe            ( mixer_strobe     ),

        .mag                     ( mag_mixer        ),
        .mag_stb                 ( mag_mixer_strobe )
    );

    always @(posedge clk ) begin
        if(~rst_n) begin
            mixer_mag_envelope <= 0;
        end else if(mag_mixer_strobe) begin
            mixer_mag_envelope <= mag_mixer >= mixer_mag_thres;   
        end
    end
endmodule