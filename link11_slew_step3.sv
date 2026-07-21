module link11_slew_step3 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [LPF_WIDTH-1:0] symbol_aligned_i,
    input wire [LPF_WIDTH-1:0] symbol_aligned_q,
    input wire symbol_aligned_strobe,
    input wire signal_valid_start,
    output wire [LPF_WIDTH-1:0] freq_corrected_i     , 
    output wire [LPF_WIDTH-1:0] freq_corrected_q     , 
    output wire                 freq_corrected_strobe 
);


localparam SYMBOL_NUM_TO_EST = 64;
localparam RAM_CACHE_DEPTH = SYMBOL_NUM_TO_EST * WINDOW_NUM + 16;

// 最开始是16, 发现精度不够, 误差太大, 改成20
localparam CORDIC_WIDTH = 30;
localparam MIXER_OUT_WIDTH = LPF_WIDTH + 16;
localparam INI_PHASE_WIDTH = 16;

// 对于每次到来信号, 只会评估一次频偏
wire phase_cor_est_strobe;
wire [CORDIC_WIDTH-2:0] phase_cor_est_i, phase_cor_est_q;
link11_slew_step3_phase_cor_est #(
    .SYMBOL_NUM_TO_EST ( SYMBOL_NUM_TO_EST ),
    .WINDOW_NUM        ( WINDOW_NUM        ),
    .LPF_WIDTH         ( LPF_WIDTH         ),
    .CORDIC_WIDTH      ( CORDIC_WIDTH      ))
 u_link11_slew_step3_phase_cor_est (
    .clk                     ( clk                                       ),
    .rst_n                   ( rst_n                                     ),
    .demod_done              ( demod_done                                ),
    .signal_valid_start      ( signal_valid_start                        ),
    .symbol_aligned_i        ( symbol_aligned_i       [LPF_WIDTH-1:0]    ),
    .symbol_aligned_q        ( symbol_aligned_q       [LPF_WIDTH-1:0]    ),
    .symbol_aligned_strobe   ( symbol_aligned_strobe                     ),

    .phase_cor_est_i         ( phase_cor_est_i        [CORDIC_WIDTH-2:0] ),
    .phase_cor_est_q         ( phase_cor_est_q        [CORDIC_WIDTH-2:0] ),
    .phase_cor_est_strobe    ( phase_cor_est_strobe                      )
);

// 在原有信号上减去评估到的频偏, symbol_aligned_strobe -> phase_corr_i 1clk个延时
wire [15:0] phase_corr_dds_i, phase_corr_dds_q;
wire                 correcting;
link11_slew_step3_phase_corr_gen #(
    .LPF_WIDTH    ( LPF_WIDTH    ),
    .CORDIC_WIDTH ( CORDIC_WIDTH ))
 u_link11_slew_step3_phase_corr_gen (
    .clk                     ( clk                                       ),
    .rst_n                   ( rst_n                                     ),
    .demod_done              ( demod_done                                ),
    .phase_cor_est_strobe    ( phase_cor_est_strobe                      ),
    .phase_cor_est_i         ( phase_cor_est_i        [CORDIC_WIDTH-2:0] ),
    .phase_cor_est_q         ( phase_cor_est_q        [CORDIC_WIDTH-2:0] ),
    .symbol_aligned_strobe   ( symbol_aligned_strobe                     ),
    .symbol_aligned_i        ( symbol_aligned_i       [LPF_WIDTH-1:0]    ),
    .symbol_aligned_q        ( symbol_aligned_q       [LPF_WIDTH-1:0]    ),

    .phase_corr_dds_i        ( phase_corr_dds_i       [15:0]             ),
    .phase_corr_dds_q        ( phase_corr_dds_q       [15:0]             ),
    .correcting              ( correcting                                )
);

// 评估相偏需要一定时间和采样点, 需要缓存原始信号, 等到correcting到来时, 开始读RAM
wire ram_cache_out_strobe;
wire [LPF_WIDTH-1:0] ram_cache_out_i, ram_cache_out_q;
link11_slew_step3_ram_cache #(
    .RAM_CACHE_DEPTH ( RAM_CACHE_DEPTH ),
    .LPF_WIDTH       ( LPF_WIDTH       ))
 u_link11_slew_step3_ram_cache (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .demod_done              ( demod_done                             ),
    .correcting              ( correcting                             ),
    .symbol_aligned_i        ( symbol_aligned_i       [LPF_WIDTH-1:0] ),
    .symbol_aligned_q        ( symbol_aligned_q       [LPF_WIDTH-1:0] ),
    .symbol_aligned_strobe   ( symbol_aligned_strobe                  ),
    .signal_valid_start      ( signal_valid_start                     ),

    .ram_cache_out_i         ( ram_cache_out_i        [LPF_WIDTH-1:0] ),
    .ram_cache_out_q         ( ram_cache_out_q        [LPF_WIDTH-1:0] ),
    .ram_cache_out_strobe    ( ram_cache_out_strobe                   )
);

// 粗频偏混频校正
link11_slew_step3_freq_corr #(
    .LPF_WIDTH ( LPF_WIDTH ))
 u_link11_slew_step3_freq_corr (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .correcting              ( correcting                             ),
    .ram_cache_out_strobe    ( ram_cache_out_strobe                   ),
    .ram_cache_out_i         ( ram_cache_out_i        [LPF_WIDTH-1:0] ),
    .ram_cache_out_q         ( ram_cache_out_q        [LPF_WIDTH-1:0] ),
    .phase_corr_dds_i        ( phase_corr_dds_i       [15:0]          ),
    .phase_corr_dds_q        ( phase_corr_dds_q       [15:0]          ),

    .freq_corrected_i        ( freq_corrected_i       [LPF_WIDTH-1:0] ),
    .freq_corrected_q        ( freq_corrected_q       [LPF_WIDTH-1:0] ),
    .freq_corrected_strobe   ( freq_corrected_strobe                  )
);
endmodule
