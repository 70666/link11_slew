module link11_slew_step4 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16,
// 这个参数指的是从1开始计数, 已知序列的最后一个数的索引, 3, 4, 5. 这个参数根据AGC损失情况设, 越大对AGC容忍程度越高
    parameter FIND_SERIES_START_INDEX = 5,
// 一共用几个前导码作互相关
    parameter SYMBOL_NUMS_TO_FIND = 3,
    parameter PREAMBLE_SYMBOL_NUM = 192
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [LPF_WIDTH-1:0] freq_corrected_i,
    input wire [LPF_WIDTH-1:0] freq_corrected_q,
    input wire freq_corrected_strobe,
    output wire [LPF_WIDTH-1:0] data_for_demod_i,
    output wire [LPF_WIDTH-1:0] data_for_demod_q,
    output wire data_for_demod_strobe,
    output wire preamble_aligned_start                      // 第一个strobe落后于start两个clk
);
localparam bit IS_POW2 = ((WINDOW_NUM) & (WINDOW_NUM-1)) == 0;
localparam AVERAGE_SAMPLE_NUM = IS_POW2 ? (WINDOW_NUM) : (1 << ($clog2(WINDOW_NUM)-1));
localparam AVERAGE_SHIFT = $clog2(AVERAGE_SAMPLE_NUM);




localparam COR_WIDTH = 2 * LPF_WIDTH + $clog2(SYMBOL_NUMS_TO_FIND);
localparam SYMBOL_INDEX_WIDTH = $clog2(PREAMBLE_SYMBOL_NUM + 1);


localparam PREAMBLE_CORRELATOR_LATENCY = 7 + $clog2(SYMBOL_NUMS_TO_FIND);
localparam SYMBOL_AVERAGE_LATENCY = AVERAGE_SHIFT + 1;

wire [LPF_WIDTH-1:0] symbol_average_i;
wire [LPF_WIDTH-1:0] symbol_average_q;
wire symbol_average_strobe;

// 求一个symbol内的相位平均值, 每个symbol只会有一个strobe产生
// 加法窗口末采样点 -> 求和结果延时为 SYMBOL_AVERAGE_LATENCY clks
link11_slew_step4_symbol_average #(
    .LPF_WIDTH  ( LPF_WIDTH  ),
    .WINDOW_NUM ( WINDOW_NUM ))
 u_symbol_average (
    .clk                     ( clk                       ),
    .rst_n                   ( rst_n                     ),
    .demod_done              ( demod_done                ),
    .data_in_i               ( freq_corrected_i          ),
    .data_in_q               ( freq_corrected_q          ),
    .data_in_strobe          ( freq_corrected_strobe     ),

    .symbol_average_i        ( symbol_average_i          ),
    .symbol_average_q        ( symbol_average_q          ),
    .symbol_average_strobe   ( symbol_average_strobe     )
);

wire [COR_WIDTH-1:0] correlation_i;
wire [COR_WIDTH-1:0] correlation_q;
wire correlation_strobe;

// 将SYMBOL_NUMS_TO_FIND个symbol与已知序列互相关, 得到自相关结果
// 当前symbol的平均 -> 自相关结果 PREAMBLE_CORRELATOR_LATENCY clks
// 在一个求和窗口的最后一个symbol, 自相关开始有效
link11_slew_step4_preamble_correlator #(
    .LPF_WIDTH                 ( LPF_WIDTH                 ),
    .SYMBOL_NUMS_TO_FIND       ( SYMBOL_NUMS_TO_FIND       ),
    .FIND_SERIES_START_INDEX   ( FIND_SERIES_START_INDEX    ),
    .PREAMBLE_SYMBOL_NUM       ( PREAMBLE_SYMBOL_NUM       ))
 u_link11_slew_step4_preamble_correlator (
    .clk                     ( clk                    ),
    .rst_n                   ( rst_n                  ),
    .demod_done              ( demod_done             ),
    .symbol_average_i        ( symbol_average_i       ),
    .symbol_average_q        ( symbol_average_q       ),
    .symbol_average_strobe   ( symbol_average_strobe  ),

    .correlation_i           ( correlation_i          ),
    .correlation_q           ( correlation_q          ),
    .correlation_strobe      ( correlation_strobe     )
);

wire [LPF_WIDTH-1:0] phase_reference_i;
wire [LPF_WIDTH-1:0] phase_reference_q;
wire [SYMBOL_INDEX_WIDTH-1:0] preamble_start_symbol_offset;
wire phase_reference_valid;

// 相关输入算出对应幅度, 找指定前导码数量内的自相关最大值, 找到后做归一化
link11_slew_step4_peak_search #(
    .LPF_WIDTH            ( LPF_WIDTH           ),
    .SYMBOL_NUMS_TO_FIND  ( SYMBOL_NUMS_TO_FIND ),
    .PREAMBLE_SYMBOL_NUM  ( PREAMBLE_SYMBOL_NUM ))
 u_peak_search (
    .clk                           ( clk                           ),
    .rst_n                         ( rst_n                         ),
    .demod_done                    ( demod_done                    ),
    .correlation_i                 ( correlation_i                 ),
    .correlation_q                 ( correlation_q                 ),
    .correlation_strobe            ( correlation_strobe            ),

    .phase_reference_i             ( phase_reference_i             ),
    .phase_reference_q             ( phase_reference_q             ),
    .preamble_start_symbol_offset  ( preamble_start_symbol_offset  ),
    .phase_reference_valid         ( phase_reference_valid         )
);

// 完成初相归一化后, 从ram中读出缓存的数据
// 第一个输出的数据是已知序列最后的下一个symbol
// start落后于strobe一个时钟
wire [LPF_WIDTH-1:0] initial_phase_corrected_i;
wire [LPF_WIDTH-1:0] initial_phase_corrected_q;
wire initial_phase_corrected_strobe;
link11_slew_step4_data_corrector #(
    .LPF_WIDTH            ( LPF_WIDTH           ),
    .WINDOW_NUM           ( WINDOW_NUM          ),
    .PREAMBLE_SYMBOL_NUM  ( PREAMBLE_SYMBOL_NUM ))
 u_data_corrector (
    .clk                            ( clk                            ),
    .rst_n                          ( rst_n                          ),
    .demod_done                     ( demod_done                     ),
    .data_in_i                      ( freq_corrected_i               ),
    .data_in_q                      ( freq_corrected_q               ),
    .data_in_strobe                 ( freq_corrected_strobe          ),
    .phase_reference_i              ( phase_reference_i              ),
    .phase_reference_q              ( phase_reference_q              ),
    .preamble_start_symbol_offset   ( preamble_start_symbol_offset   ),
    .phase_reference_valid          ( phase_reference_valid          ),

    .data_out_i                     ( initial_phase_corrected_i      ),
    .data_out_q                     ( initial_phase_corrected_q      ),
    .data_out_strobe                ( initial_phase_corrected_strobe ),
    .preamble_aligned_start         ( preamble_aligned_start         )
);

wire [2*LPF_WIDTH:0] ini_phase_bundle;
assign ini_phase_bundle = {initial_phase_corrected_strobe, initial_phase_corrected_q, initial_phase_corrected_i};
wire [2*LPF_WIDTH:0] ini_phase_bundle_delayed;
assign data_for_demod_strobe = ini_phase_bundle_delayed[2*LPF_WIDTH];
assign data_for_demod_q = ini_phase_bundle_delayed[2*LPF_WIDTH-1:LPF_WIDTH];
assign data_for_demod_i = ini_phase_bundle_delayed[LPF_WIDTH-1:0];
delay #(
    .DATA_WIDTH ( 2*LPF_WIDTH + 1   ),
    .DELAY_CLK  ( 3                 ),
    .IMPL_TYPE  ( 0                 ))
 u_delay (
    .clk        ( clk                   ),
    .data_in    ( ini_phase_bundle      ),

    .data_out   ( ini_phase_bundle_delayed )
);
endmodule
