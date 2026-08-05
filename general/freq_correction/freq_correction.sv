/*
    输入: 一个去掉前导码相位的理论直流信号
    输出: 一个频偏校准 + 初相剔除的信号
    使用的DDS ip核相位位宽必须是 CORDIC输出位宽-2, 幅度位宽必须是16, CORDIC输入输出位宽必须相同
    每次希望更改相位精度时, 改CORDIC ip和DDS ip相位位宽以及参数CORDIC_WIDTH即可, DDS相位位宽是CORDIC位宽-2
*/
module freq_correction #(
    parameter SYMBOL_DATA_WIDTH = 16,   // 原始symbol数据位宽
    parameter DEROT_DATA_WIDTH = 21,    // 去旋转后的symbol位宽
    parameter SYMBOL_INTERVAL = 32,     // 前导码相位作差SYMBOL间隔, 必须是power2
    parameter CORDIC_WIDTH = 32         // 2*DATA_WIDTH+$clog2(SYMBOL_INTERVAL)-1 > CORDIC_WIDTH
) (
    input wire clk,
    input wire rst_n,                                       // 同步低有效复位
    input wire [15:0] first_preamble_standard_i     ,       // symbol_start后首个前导码标准相位 16bit有符号数
    input wire [15:0] first_preamble_standard_q     ,
    input wire symbol_start,                                // 复位标志, 每次消息只有一次, 是信号到来的开始标志
    input wire symbol_strobe,                               // 一个symbol只有一个采样点, 这个采样点是所有采样点的平均
    input wire [SYMBOL_DATA_WIDTH-1:0] symbol_i, symbol_q,  // 一个symbol内所有采样点的平均
    input wire symbol_envelope,                             // symbol的包络, 和数据同时缓冲
    input wire [DEROT_DATA_WIDTH-1:0] preamble_derot_i,     // symbol使用mixer去掉了旋转的前导码, 比symbol落后几个时钟
    input wire [DEROT_DATA_WIDTH-1:0] preamble_derot_q,     // 理论上来说是一个只有频偏的直流分量, 不允许
    input wire preamble_derot_strobe,

    output wire                    data_for_demod_start ,   // 给下个模块的复位标志
    output wire                    data_for_demod_strobe,   // 每个symbol一个strobe
    output wire [2*SYMBOL_DATA_WIDTH-1:0] data_for_demod_i, // 剔除掉频偏和初相的信号
    output wire [2*SYMBOL_DATA_WIDTH-1:0] data_for_demod_q, 
    output wire envelope_for_demod        
);

localparam RAM_CACHE_DEPTH = 2*SYMBOL_INTERVAL + 7 + 10;    // 给予RAM一定裕量(10)
localparam RAM_WRITE_WIDTH = 2*SYMBOL_DATA_WIDTH + 1;
localparam MIXER_LATENCY = 7;
localparam FREQ_CORRECT_LATENCY = 3*MIXER_LATENCY + 2;      // 从RAM输出到解调数据延时

//  使用 前导码部分 自相关估计出频偏, 得到DDS校正信号
wire        correcting  ;                   // 频偏校准波形生成中
wire [15:0] phase_corr_dds_i;               // 频偏校准DDS信号
wire [15:0] phase_corr_dds_q;
freq_estimation #(
    .SYMBOL_INTERVAL  ( SYMBOL_INTERVAL  ),
    .DEROT_DATA_WIDTH ( DEROT_DATA_WIDTH ),
    .CORDIC_WIDTH     ( CORDIC_WIDTH     ))
 u_freq_estimation (
    .clk                     ( clk                                           ),
    .rst_n                   ( rst_n                                         ),
    .symbol_start            ( symbol_start                                  ),
    .preamble_derot_strobe   ( preamble_derot_strobe                         ),
    .preamble_derot_i        ( preamble_derot_i       [DEROT_DATA_WIDTH-1:0] ),
    .preamble_derot_q        ( preamble_derot_q       [DEROT_DATA_WIDTH-1:0] ),

    .correcting              ( correcting                                    ),
    .phase_corr_dds_i        ( phase_corr_dds_i       [15:0]                 ),
    .phase_corr_dds_q        ( phase_corr_dds_q       [15:0]                 )
);

//  原始信号缓存, 给予频偏估计 操作时间
wire [RAM_WRITE_WIDTH-1:0] ram_cache_out    ;
wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_i; // 缓存输出信号
wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_q;
wire ram_cache_out_envelope                 ;
wire                  ram_cache_out_strobe;
wire [RAM_WRITE_WIDTH-1:0] symbol = {symbol_envelope, symbol_q, symbol_i};
assign ram_cache_out_i = ram_cache_out[SYMBOL_DATA_WIDTH-1:0];
assign ram_cache_out_q = ram_cache_out[2*SYMBOL_DATA_WIDTH-1:SYMBOL_DATA_WIDTH];
assign ram_cache_out_envelope = ram_cache_out[2*SYMBOL_DATA_WIDTH];
ram_cache #(
    .RAM_CACHE_DEPTH ( RAM_CACHE_DEPTH ),
    .RAM_WRITE_WIDTH ( RAM_WRITE_WIDTH ))
 u_ram_cache (
    .clk                     ( clk                                         ),
    .rst_n                   ( rst_n                                       ),
    .symbol_start            ( symbol_start                                ),
    .correcting              ( correcting                                  ),
    .symbol                  ( symbol                [RAM_WRITE_WIDTH-1:0] ),
    .symbol_strobe           ( symbol_strobe                               ),

    .ram_cache_out           ( ram_cache_out         [RAM_WRITE_WIDTH-1:0] ),
    .ram_cache_out_strobe    ( ram_cache_out_strobe                        )
);
//  混频校正
wire                         freq_corrected_strobe;
wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_i     ;    // 频偏校正后信号
wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_q     ;
freq_diff_correct #(
    .SYMBOL_DATA_WIDTH ( SYMBOL_DATA_WIDTH ))
 u_freq_diff_correct (
    .clk                     ( clk                                            ),
    .rst_n                   ( rst_n                                          ),
    .correcting              ( correcting                                     ),
    .ram_cache_out_strobe    ( ram_cache_out_strobe                           ),
    .ram_cache_out_i         ( ram_cache_out_i        [SYMBOL_DATA_WIDTH-1:0] ),
    .ram_cache_out_q         ( ram_cache_out_q        [SYMBOL_DATA_WIDTH-1:0] ),
    .phase_corr_dds_i        ( phase_corr_dds_i       [15:0]                  ),
    .phase_corr_dds_q        ( phase_corr_dds_q       [15:0]                  ),

    .freq_corrected_i        ( freq_corrected_i       [SYMBOL_DATA_WIDTH-1:0] ),
    .freq_corrected_q        ( freq_corrected_q       [SYMBOL_DATA_WIDTH-1:0] ),
    .freq_corrected_strobe   ( freq_corrected_strobe                          )
);

// 初相校正
init_phase_correct #(
    .SYMBOL_DATA_WIDTH ( SYMBOL_DATA_WIDTH ))
 u_init_phase_correct (
    .clk                        ( clk                                                  ),
    .rst_n                      ( rst_n                                                ),
    .first_preamble_standard_i  ( first_preamble_standard_i  [15:0]                    ),
    .first_preamble_standard_q  ( first_preamble_standard_q  [15:0]                    ),
    .freq_corrected_i           ( freq_corrected_i           [SYMBOL_DATA_WIDTH-1:0]   ),
    .freq_corrected_q           ( freq_corrected_q           [SYMBOL_DATA_WIDTH-1:0]   ),
    .freq_corrected_strobe      ( freq_corrected_strobe                                ),
    .symbol_start               ( symbol_start                                         ),

    .data_for_demod_start       ( data_for_demod_start                                 ),
    .data_for_demod_strobe      ( data_for_demod_strobe                                ),
    .data_for_demod_i           ( data_for_demod_i           [2*SYMBOL_DATA_WIDTH-1:0] ),
    .data_for_demod_q           ( data_for_demod_q           [2*SYMBOL_DATA_WIDTH-1:0] )
);

delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( FREQ_CORRECT_LATENCY ),
    .IMPL_TYPE  ( 0  ))
 u_delay (
    .clk        ( clk                      ),
    .data_in    ( ram_cache_out_envelope   ),

    .data_out   ( envelope_for_demod       )
);
endmodule