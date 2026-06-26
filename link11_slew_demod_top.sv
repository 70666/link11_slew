module link11_slew_demod_top #(
    parameter DATA_WIDTH = 16,
    parameter WINDOW_NUM = 16,     // 一个符号对应采样点个数
    parameter STANDARD_1800_PHASE_INC = 1600   // 16bit, 1800 * 65536 / sample clk freq
) (
    input wire clk,
    input wire rst_n,
    input wire signal_if_strobe,
    input wire [DATA_WIDTH-1:0] signal_if_i,
    input wire [DATA_WIDTH-1:0] signal_if_q,
    input wire [2*DATA_WIDTH-1:0] envelope_detection
);
    
// 位宽
localparam DDS_PATTERN_WIDTH = 8;       // 可随便设小于等于16
localparam DDS_PHASE_WIDTH = 16;        // IP核设置
localparam LPF_WIDTH = 16;


// 延时



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

// 第二步, 根据包络和一个窗口内的累加峰值, 找到symbol边界
wire demod_done;                                            // 后续解调模块给出, 一条消息彻底结束
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

// 第三步, 根据前后相位差估计出频偏, 使用DDS生成对应信号, 并将频偏减去, 得到绝对相位
wire [LPF_WIDTH-1:0] freq_corrected_i     ; 
wire [LPF_WIDTH-1:0] freq_corrected_q     ; 
wire                 freq_corrected_strobe;
link11_slew_step3 #(
    .LPF_WIDTH  ( LPF_WIDTH  ),
    .WINDOW_NUM ( WINDOW_NUM ))
 u_link11_slew_step3 (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .demod_done              ( demod_done                             ),
    .symbol_aligned_i        ( symbol_aligned_i       [LPF_WIDTH-1:0] ),
    .symbol_aligned_q        ( symbol_aligned_q       [LPF_WIDTH-1:0] ),
    .symbol_aligned_strobe   ( symbol_aligned_strobe                  ),
    .signal_valid_start      ( signal_valid_start                     ),

    .freq_corrected_i        ( freq_corrected_i       [LPF_WIDTH-1:0] ),
    .freq_corrected_q        ( freq_corrected_q       [LPF_WIDTH-1:0] ),
    .freq_corrected_strobe   ( freq_corrected_strobe                  )
);


// 第一个输出的数据是已知序列最后的下一个symbol
// start落后于strobe一个时钟
// 第四步, 根据已知前导码, 在窗口内求和找到前导码的边界, 并对粗频偏校正信号进行初相校正
wire [LPF_WIDTH-1:0] initial_phase_corrected_i;
wire [LPF_WIDTH-1:0] initial_phase_corrected_q;
wire initial_phase_corrected_strobe;
wire preamble_aligned_start;
link11_slew_step4 #(
    .LPF_WIDTH           ( LPF_WIDTH  ),
    .WINDOW_NUM          ( WINDOW_NUM ),
    .PREAMBLE_SYMBOL_NUM ( 192        ))
 u_link11_slew_step4 (
    .clk                            ( clk                            ),
    .rst_n                          ( rst_n                          ),
    .demod_done                     ( demod_done                     ),
    .freq_corrected_i               ( freq_corrected_i               ),
    .freq_corrected_q               ( freq_corrected_q               ),
    .freq_corrected_strobe          ( freq_corrected_strobe          ),

    .initial_phase_corrected_i      ( initial_phase_corrected_i      ),
    .initial_phase_corrected_q      ( initial_phase_corrected_q      ),
    .initial_phase_corrected_strobe ( initial_phase_corrected_strobe ),
    .preamble_aligned_start         ( preamble_aligned_start         )
);

// 第五步, 前导码训练均衡器


endmodule