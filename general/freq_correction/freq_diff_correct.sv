module freq_diff_correct #(
    parameter SYMBOL_DATA_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire correcting,
    input wire ram_cache_out_strobe,
    input wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_i, ram_cache_out_q,
    input wire [15:0] phase_corr_dds_i, phase_corr_dds_q,
    output wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_i, freq_corrected_q,
    output wire freq_corrected_strobe
);


localparam  MIXER_OUT_WIDTH = SYMBOL_DATA_WIDTH + 16;
// 将频偏去掉, 得到一个彻底零中频的信号 
// phase_corr 相对于 ram_cache_out 早了ram_latency个clks, 但是因为采样点之间间隔很大, 因此可以忽略不记
wire mixer_out_strobe;
wire [MIXER_OUT_WIDTH-1:0] oi, oq;
wire [SYMBOL_DATA_WIDTH-1:0] mixer_out_i, mixer_out_q;
assign mixer_out_i = oi[MIXER_OUT_WIDTH-2-:SYMBOL_DATA_WIDTH];
assign mixer_out_q = oq[MIXER_OUT_WIDTH-2-:SYMBOL_DATA_WIDTH];
assign freq_corrected_i = mixer_out_i;
assign freq_corrected_q = mixer_out_q;
assign freq_corrected_strobe = mixer_out_strobe;
mixer_strobe #(
    .A_DATA_WIDTH ( SYMBOL_DATA_WIDTH   ),
    .B_DATA_WIDTH ( 16          ),
    .IMPL_TYPE    ( "LUT"       ),
    .MODE         ( 0           ))
 u_mixer_strobe_phase_corr (
    .clk          ( clk                    ),
    .rst_n        ( rst_n                  ),
    .in_strobe    ( ram_cache_out_strobe   ),
    .ai           ( ram_cache_out_i        ),
    .aq           ( ram_cache_out_q        ),
    .bi           ( phase_corr_dds_i       ),
    .bq           ( phase_corr_dds_q       ),

    .out_strobe   ( mixer_out_strobe       ),
    .oi           ( oi                     ),
    .oq           ( oq                     )
);

endmodule