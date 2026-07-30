module link11_slew_demod_top #(
    parameter DATA_WIDTH = 16,                          // 输入中频的位宽
    parameter WINDOW_NUM = 16,                          // 一个符号对应采样点个数
    parameter STANDARD_1800_PHASE_INC = 1600            // 16bit, 1800 * 65536 / sample clk freq
) (
    input wire clk,
    input wire rst_n,
    input wire device_type,                             // 1:PICKET 0:NCS
    input wire signal_if_strobe,                        // 中频信号strobe
    input wire [DATA_WIDTH-1:0] signal_if_i,            // 中频信号
    input wire [DATA_WIDTH-1:0] signal_if_q,
    input wire [2*DATA_WIDTH-1:0] envelope_detection,   // 前导码检测信号包络阈值
    input wire [31:0] mixer_mag_thres       ,           // 结束解调信号消失包络阈值
    output wire        viterbi_done         ,
    output wire [59:0] decoded_bits         ,
    output wire [5:0]  decoded_length       ,
    output wire [5:0]  best_start_state     ,
    output wire [7:0]  best_path_metric     ,
    output wire        crc_check_pass       ,
    output wire        crc_check_strobe     
);
    
// 位宽
localparam DDS_PATTERN_WIDTH = 16;      // 为了保持精度, 请至少设为16
localparam DDS_PHASE_WIDTH = 16;        // IP核设置
localparam LPF_WIDTH = 16;
// 检测前导码序列的起始index, 从0开始计数, 这个参数根据AGC损失情况设, 越大对AGC容忍程度越高
localparam FIND_SERIES_START_INDEX = 5;
// 前导码检测序列的长度
localparam SYMBOL_NUMS_TO_FIND = 10;
// 前导码对齐后, 输出的第一个symbol对应的index, 这个值最多不超过192-64, 要给后面留足够的空间进行细频偏估计
localparam KNOWN_SEQUENCE_END_SYMBOL = FIND_SERIES_START_INDEX + SYMBOL_NUMS_TO_FIND - 1;


// 模拟域的处理, 不是状态机里的一部分
// 第一步, 下变频去掉1800Hz固定旋转 + 低通滤波滤除高频干扰 + 包络检波检测信号到来
wire envelope;
wire [LPF_WIDTH-1:0] signal_lpf_envelope_i, signal_lpf_envelope_q;    
wire signal_lpf_envelope_strobe; 
link11_slew_step1 #(
    .LPF_WIDTH               ( LPF_WIDTH               ),
    .DATA_WIDTH              ( DATA_WIDTH              ),
    .WINDOW_NUM              ( WINDOW_NUM              ),
    .DDS_PATTERN_WIDTH       ( DDS_PATTERN_WIDTH       ),
    .DDS_PHASE_WIDTH         ( DDS_PHASE_WIDTH         ),
    .STANDARD_1800_PHASE_INC ( STANDARD_1800_PHASE_INC ))
 u_link11_slew_step1 (
    .clk                         ( clk                                           ),
    .rst_n                       ( rst_n                                         ),
    .signal_if_strobe            ( signal_if_strobe                              ),
    .signal_if_i                 ( signal_if_i                 [DATA_WIDTH-1:0]  ),
    .signal_if_q                 ( signal_if_q                 [DATA_WIDTH-1:0]  ),
    .envelope_detection          ( envelope_detection          [2*LPF_WIDTH-1:0] ),

    .envelope                    ( envelope                                      ),
    .signal_lpf_envelope_i       ( signal_lpf_envelope_i       [LPF_WIDTH-1:0]   ),
    .signal_lpf_envelope_q       ( signal_lpf_envelope_q       [LPF_WIDTH-1:0]   ),
    .signal_lpf_envelope_strobe  ( signal_lpf_envelope_strobe                    )
);

// 第二步, symbol边界对齐, 输出的是最可能symbol边界的下一个symbol
wire demod_done;                                            // 后续解调模块给出, 代表一条消息彻底结束
wire [LPF_WIDTH-1:0] symbol_aligned_i, symbol_aligned_q;    // symbol边界对齐后的信号
wire symbol_aligned_strobe;                                 // 采样点strobe
wire signal_valid_start;                                    // 检测到信号
link11_slew_step2 #(
    .LPF_WIDTH  ( LPF_WIDTH  ),
    .WINDOW_NUM ( WINDOW_NUM ))
 u_link11_slew_step2 (
    .clk                         ( clk                                                  ),
    .rst_n                       ( rst_n                                                ),
    .demod_done                  ( demod_done                                           ),
    .envelope                    ( envelope                                             ),
    .signal_lpf_envelope_i       ( signal_lpf_envelope_i                [LPF_WIDTH-1:0] ),
    .signal_lpf_envelope_q       ( signal_lpf_envelope_q                [LPF_WIDTH-1:0] ),
    .signal_lpf_envelope_strobe  ( signal_lpf_envelope_strobe                           ),

    .symbol_aligned_i            ( symbol_aligned_i                     [LPF_WIDTH-1:0] ),
    .symbol_aligned_q            ( symbol_aligned_q                     [LPF_WIDTH-1:0] ),
    .symbol_aligned_strobe       ( symbol_aligned_strobe                                ),
    .signal_valid_start          ( signal_valid_start                                   )
);

// 第三步, 粗频偏校正
wire [LPF_WIDTH-1:0] freq_corrected_i     ; 
wire [LPF_WIDTH-1:0] freq_corrected_q     ; 
wire                 freq_corrected_strobe;
wire                 freq_corrected_start;
link11_slew_step3 #(
    .LPF_WIDTH  ( LPF_WIDTH  ),
    .WINDOW_NUM ( WINDOW_NUM ))
 u_link11_slew_step3 (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .symbol_aligned_i        ( symbol_aligned_i       [LPF_WIDTH-1:0] ),
    .symbol_aligned_q        ( symbol_aligned_q       [LPF_WIDTH-1:0] ),
    .symbol_aligned_strobe   ( symbol_aligned_strobe                  ),
    .signal_valid_start      ( signal_valid_start                     ),

    .freq_corrected_i        ( freq_corrected_i       [LPF_WIDTH-1:0] ),
    .freq_corrected_q        ( freq_corrected_q       [LPF_WIDTH-1:0] ),
    .freq_corrected_strobe   ( freq_corrected_strobe                  ),
    .freq_corrected_start    ( freq_corrected_start                   )
);


// 第四步, 根据已知前导码, 在窗口内求和找到前导码的边界, 输出的第一个数据是KNOWN_SEQUENCE_END_SYMBOL下一个索引
wire preamble_aligned_start                 ;
wire [2*LPF_WIDTH-1:0] preamble_aligned_data;
wire preamble_aligned_probe                 ;
link11_slew_step4 #(
    .LPF_WIDTH               ( LPF_WIDTH               ),
    .WINDOW_NUM              ( WINDOW_NUM              ),
    .FIND_SERIES_START_INDEX ( FIND_SERIES_START_INDEX ),
    .SYMBOL_NUMS_TO_FIND     ( SYMBOL_NUMS_TO_FIND     ),
    .PREAMBLE_SYMBOL_NUM     ( 192                     ))
 u_link11_slew_step4 (
    .clk                     ( clk                                       ),
    .rst_n                   ( rst_n                                     ),
    .freq_corrected_start    ( freq_corrected_start                      ),
    .freq_corrected_i        ( freq_corrected_i        [LPF_WIDTH-1:0]   ),
    .freq_corrected_q        ( freq_corrected_q        [LPF_WIDTH-1:0]   ),
    .freq_corrected_strobe   ( freq_corrected_strobe                     ),

    .preamble_aligned_start  ( preamble_aligned_start                    ),
    .preamble_aligned_data   ( preamble_aligned_data   [2*LPF_WIDTH-1:0] ),
    .preamble_aligned_probe  ( preamble_aligned_probe                    )
);
// 第五步, 前导码训练均衡器
localparam EQ_WIDTH = 2*(LPF_WIDTH+$clog2(WINDOW_NUM));
wire [EQ_WIDTH-1:0] equalized_i;
wire [EQ_WIDTH-1:0] equalized_q;
wire equalized_strobe;
wire equalized_start;
wire data_for_demod_start ;
wire data_for_demod_strobe;
wire [EQ_WIDTH-1:0] data_for_demod_i;
wire [EQ_WIDTH-1:0] data_for_demod_q;
assign equalized_i      = data_for_demod_i;
assign equalized_q      = data_for_demod_q;
assign equalized_strobe = data_for_demod_strobe;
assign equalized_start  = data_for_demod_start;
link11_slew_step5 #(
    .LPF_WIDTH                 ( LPF_WIDTH                 ),
    .WINDOW_NUM                ( WINDOW_NUM                ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
 u_link11_slew_step5 (
    .clk                     ( clk                                                            ),
    .rst_n                   ( rst_n                                                          ),
    .preamble_aligned_start  ( preamble_aligned_start                                         ),
    .preamble_aligned_data   ( preamble_aligned_data   [2*LPF_WIDTH-1:0]                      ),
    .preamble_aligned_probe  ( preamble_aligned_probe                                         ),

    .data_for_demod_start    ( data_for_demod_start                                           ),
    .data_for_demod_strobe   ( data_for_demod_strobe                                          ),
    .data_for_demod_i        ( data_for_demod_i        [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] ),
    .data_for_demod_q        ( data_for_demod_q        [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] )
);

// 第六步, 根据需要解调的IQ信号, 以及本地产生的加扰信号, 反推出加扰前的信号, 再经过QPSK解调, 得到dibit
wire [1:0] dibit;
wire dibit_strobe;
wire mixer_mag_envelope;
link11_slew_step6 #(
    .EQ_WIDTH                  ( EQ_WIDTH                  ),
    .WINDOW_NUM                ( WINDOW_NUM                ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
 u_link11_slew_step6 (
    .clk                     ( clk                              ),
    .rst_n                   ( rst_n                            ),
    .mixer_mag_thres         ( mixer_mag_thres                  ),
    .equalized_i             ( equalized_i       [EQ_WIDTH-1:0] ),
    .equalized_q             ( equalized_q       [EQ_WIDTH-1:0] ),
    .equalized_strobe        ( equalized_strobe                 ),
    .equalized_start         ( equalized_start                  ),

    .dibit                   ( dibit             [1:0]          ),
    .dibit_strobe            ( dibit_strobe                     ),
    .mixer_mag_envelope      ( mixer_mag_envelope               )
);

// 第七步, dibit数字域处理: 1解交织 2解卷积编码 3CRC验错
link11_slew_step7  u_link11_slew_step7 (
    .clk                     ( clk                        ),
    .rst_n                   ( rst_n                      ),
    .device_type             ( device_type                ),
    .dibit                   ( dibit               [1:0]  ),
    .dibit_strobe            ( dibit_strobe               ),
    .equalized_start         ( equalized_start            ),
    .mixer_mag_envelope      ( mixer_mag_envelope         ),

    .viterbi_done            ( viterbi_done               ),
    .decoded_bits            ( decoded_bits        [59:0] ),
    .decoded_length          ( decoded_length      [5:0]  ),
    .best_start_state        ( best_start_state    [5:0]  ),
    .best_path_metric        ( best_path_metric    [7:0]  ),
    .crc_check_pass          ( crc_check_pass             ),
    .crc_check_strobe        ( crc_check_strobe           ),
    .demod_done              ( demod_done                 )
);
endmodule