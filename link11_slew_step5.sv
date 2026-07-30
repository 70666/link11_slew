module link11_slew_step5 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 16
) (
    input wire clk,
    input wire rst_n,
    input wire                   preamble_aligned_start,
    input wire [2*LPF_WIDTH-1:0] preamble_aligned_data ,
    input wire                   preamble_aligned_probe,
    output wire                                        data_for_demod_start ,  
    output wire                                        data_for_demod_strobe,  
    output wire [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] data_for_demod_i     ,  
    output wire [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] data_for_demod_q       
);


wire [LPF_WIDTH-1:0] preamble_aligned_data_i, preamble_aligned_data_q;
assign preamble_aligned_data_q = preamble_aligned_data[2*LPF_WIDTH-1:LPF_WIDTH];
assign preamble_aligned_data_i = preamble_aligned_data[LPF_WIDTH-1:0];

localparam SYMBOL_INTERVAL = 32;
localparam PREAMBLE_SYMBOL_NUM = 192;

localparam WINDOW_NUM_WIDTH = $clog2(WINDOW_NUM);
localparam SYMBOL_DATA_WIDTH = LPF_WIDTH + WINDOW_NUM_WIDTH;
localparam CORDIC_WIDTH = 32;
localparam DEROT_DATA_WIDTH = SYMBOL_DATA_WIDTH + 15;

localparam ADDER_LATENCY = 2;
localparam MIXER_LATENCY = 7;

// 将samples转换成symbol
wire symbol_start = preamble_aligned_start;
wire                         symbol_strobe;           
wire [SYMBOL_DATA_WIDTH-1:0] symbol_i     ;           
wire [SYMBOL_DATA_WIDTH-1:0] symbol_q     ;           
link11_slew_step5_samples_to_symbol #(
    .LPF_WIDTH                 ( LPF_WIDTH                 ),
    .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
    .ADDER_IMPL_TYPE           ( "DSP"                      ),
    .ADDER_LATENCY             ( ADDER_LATENCY             ),
    .WINDOW_NUM_WIDTH          ( WINDOW_NUM_WIDTH          ),
    .WINDOW_NUM                ( WINDOW_NUM                ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
 u_link11_slew_step5_samples_to_symbol (
    .clk                      ( clk                                              ),
    .rst_n                    ( rst_n                                            ),
    .preamble_aligned_start   ( preamble_aligned_start                           ),
    .preamble_aligned_data_i  ( preamble_aligned_data_i  [LPF_WIDTH-1:0]         ),
    .preamble_aligned_data_q  ( preamble_aligned_data_q  [LPF_WIDTH-1:0]         ),
    .preamble_aligned_probe   ( preamble_aligned_probe                           ),

    .symbol_strobe            ( symbol_strobe                                    ),
    .symbol_i                 ( symbol_i                 [SYMBOL_DATA_WIDTH-1:0] ),
    .symbol_q                 ( symbol_q                 [SYMBOL_DATA_WIDTH-1:0] )
);


wire                        preamble_derot_strobe;
wire [DEROT_DATA_WIDTH-1:0] preamble_derot_i     ;
wire [DEROT_DATA_WIDTH-1:0] preamble_derot_q     ;
link11_slew_step5_derot #(
    .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
    .DEROT_DATA_WIDTH          ( DEROT_DATA_WIDTH          ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ),
    .PREAMBLE_SYMBOL_NUM       ( PREAMBLE_SYMBOL_NUM       ),
    .SYMBOL_INTERVAL           ( SYMBOL_INTERVAL           ))
 u_link11_slew_step5_derot (
    .clk                     ( clk                                            ),
    .rst_n                   ( rst_n                                          ),
    .symbol_start            ( symbol_start                                   ),
    .symbol_strobe           ( symbol_strobe                                  ),
    .symbol_i                ( symbol_i               [SYMBOL_DATA_WIDTH-1:0] ),
    .symbol_q                ( symbol_q               [SYMBOL_DATA_WIDTH-1:0] ),

    .preamble_derot_strobe   ( preamble_derot_strobe                          ),
    .preamble_derot_i        ( preamble_derot_i       [DEROT_DATA_WIDTH-1:0]  ),
    .preamble_derot_q        ( preamble_derot_q       [DEROT_DATA_WIDTH-1:0]  )
);

`include "link11_slew_preamble_iq_wire.vh"
`LINK11_SLEW_PREAMBLE_IQ_WIRE_DECLARE
wire [15:0] first_preamble_standard_i = LINK11_SLEW_PREAMBLE_I[KNOWN_SEQUENCE_END_SYMBOL+1];
wire [15:0] first_preamble_standard_q = LINK11_SLEW_PREAMBLE_Q[KNOWN_SEQUENCE_END_SYMBOL+1];
freq_correction #(
    .SYMBOL_DATA_WIDTH ( SYMBOL_DATA_WIDTH ),
    .DEROT_DATA_WIDTH  ( DEROT_DATA_WIDTH  ),
    .SYMBOL_INTERVAL   ( SYMBOL_INTERVAL   ),
    .CORDIC_WIDTH      ( CORDIC_WIDTH      ))
 u_freq_correction (
    .clk                        ( clk                                                  ),
    .rst_n                      ( rst_n                                                ),
    .first_preamble_standard_i  ( first_preamble_standard_i  [15:0]                    ),
    .first_preamble_standard_q  ( first_preamble_standard_q  [15:0]                    ),
    .symbol_start               ( symbol_start                                         ),
    .symbol_strobe              ( symbol_strobe                                        ),
    .symbol_i                   ( symbol_i                   [SYMBOL_DATA_WIDTH-1:0]   ),
    .symbol_q                   ( symbol_q                   [SYMBOL_DATA_WIDTH-1:0]   ),
    .preamble_derot_i           ( preamble_derot_i           [DEROT_DATA_WIDTH-1:0]    ),
    .preamble_derot_q           ( preamble_derot_q           [DEROT_DATA_WIDTH-1:0]    ),
    .preamble_derot_strobe      ( preamble_derot_strobe                                ),

    .data_for_demod_start       ( data_for_demod_start                                 ),
    .data_for_demod_strobe      ( data_for_demod_strobe                                ),
    .data_for_demod_i           ( data_for_demod_i           [2*SYMBOL_DATA_WIDTH-1:0] ),
    .data_for_demod_q           ( data_for_demod_q           [2*SYMBOL_DATA_WIDTH-1:0] )
);
// wire symbol_strobe;
// wire [SYMBOL_DATA_WIDTH-1:0] symbol_i, symbol_q;
// wire normalized;
// wire [30:0] normalized_i, normalized_q;
// link11_slew_step5_phase_est #(
//     .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
//     .LPF_WIDTH                 ( LPF_WIDTH                 ),
//     .ADDER_LATENCY             ( ADDER_LATENCY             ),
//     .WINDOW_NUM_WIDTH          ( WINDOW_NUM_WIDTH          ),
//     .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ),
//     .WINDOW_NUM                ( WINDOW_NUM                ),
//     .CORDIC_WIDTH              ( CORDIC_WIDTH              ))
//  u_link11_slew_step5_phase_est (
//     .clk                      ( clk                                              ),
//     .rst_n                    ( rst_n                                            ),
//     .preamble_aligned_start   ( preamble_aligned_start                           ),
//     .preamble_aligned_probe   ( preamble_aligned_probe                           ),
//     .preamble_aligned_data_i  ( preamble_aligned_data_i  [LPF_WIDTH-1:0]         ),
//     .preamble_aligned_data_q  ( preamble_aligned_data_q  [LPF_WIDTH-1:0]         ),

//     .symbol_i                 ( symbol_i                 [SYMBOL_DATA_WIDTH-1:0] ),
//     .symbol_q                 ( symbol_q                 [SYMBOL_DATA_WIDTH-1:0] ),
//     .symbol_strobe            ( symbol_strobe                                    ),
//     .normalized               ( normalized                                       ),
//     .normalized_i             ( normalized_i             [CORDIC_WIDTH-2:0]      ),
//     .normalized_q             ( normalized_q             [CORDIC_WIDTH-2:0]      )
// );

// wire phase_cor_est_strobe = normalized;
// wire [CORDIC_WIDTH-2:0] phase_cor_est_i = normalized_i;      
// wire [CORDIC_WIDTH-2:0] phase_cor_est_q = normalized_q;    
// wire [15:0] phase_corr_dds_i, phase_corr_dds_q;
// wire correcting;  
// link11_slew_step5_phase_corr_gen #(
//     .CORDIC_WIDTH ( CORDIC_WIDTH ))
//  u_link11_slew_step5_phase_corr_gen (
//     .clk                     ( clk                                        ),
//     .rst_n                   ( rst_n                                      ),
//     .preamble_aligned_start  ( preamble_aligned_start                     ),
//     .phase_cor_est_strobe    ( phase_cor_est_strobe                       ),
//     .phase_cor_est_i         ( phase_cor_est_i         [CORDIC_WIDTH-2:0] ),
//     .phase_cor_est_q         ( phase_cor_est_q         [CORDIC_WIDTH-2:0] ),
//     .symbol_strobe           ( symbol_strobe                              ),

//     .phase_corr_dds_i        ( phase_corr_dds_i        [15:0]             ),
//     .phase_corr_dds_q        ( phase_corr_dds_q        [15:0]             ),
//     .correcting              ( correcting                                 )
// );



// // ram将签到码对齐的数据存起来, 等到dds准备好时, 再放出
// localparam RAM_CACHE_DEPTH     = 192 + 64;                 // 192 + 细频偏 处理时间
// wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_i;         
// wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_q;         
// wire ram_cache_out_strobe;                           
// link11_slew_step5_ram_cache #(
//     .RAM_CACHE_DEPTH   ( RAM_CACHE_DEPTH   ),
//     .SYMBOL_DATA_WIDTH ( SYMBOL_DATA_WIDTH ))
//  u_link11_slew_step5_ram_cache (
//     .clk                     ( clk                                             ),
//     .rst_n                   ( rst_n                                           ),
//     .correcting              ( correcting                                      ),
//     .symbol_i                ( symbol_i                [SYMBOL_DATA_WIDTH-1:0] ),
//     .symbol_q                ( symbol_q                [SYMBOL_DATA_WIDTH-1:0] ),
//     .symbol_strobe           ( symbol_strobe                                   ),
//     .preamble_aligned_start  ( preamble_aligned_start                          ),

//     .ram_cache_out_i         ( ram_cache_out_i         [SYMBOL_DATA_WIDTH-1:0] ),
//     .ram_cache_out_q         ( ram_cache_out_q         [SYMBOL_DATA_WIDTH-1:0] ),
//     .ram_cache_out_strobe    ( ram_cache_out_strobe                            )
// );


// wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_i     ;
// wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_q     ;
// wire                         freq_corrected_strobe;
// link11_slew_step5_freq_corr #(
//     .SYMBOL_DATA_WIDTH ( SYMBOL_DATA_WIDTH ))
//  u_link11_slew_step5_freq_corr (
//     .clk                     ( clk                                            ),
//     .rst_n                   ( rst_n                                          ),
//     .correcting              ( correcting                                     ),
//     .ram_cache_out_strobe    ( ram_cache_out_strobe                           ),
//     .ram_cache_out_i         ( ram_cache_out_i        [SYMBOL_DATA_WIDTH-1:0] ),
//     .ram_cache_out_q         ( ram_cache_out_q        [SYMBOL_DATA_WIDTH-1:0] ),
//     .phase_corr_dds_i        ( phase_corr_dds_i       [15:0]                  ),
//     .phase_corr_dds_q        ( phase_corr_dds_q       [15:0]                  ),

//     .freq_corrected_i        ( freq_corrected_i       [SYMBOL_DATA_WIDTH-1:0] ),
//     .freq_corrected_q        ( freq_corrected_q       [SYMBOL_DATA_WIDTH-1:0] ),
//     .freq_corrected_strobe   ( freq_corrected_strobe                          )
// );

// link11_slew_step5_initial_phase_corr #(
//     .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
//     .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
//  u_link11_slew_step5_initial_phase_corr (
//     .clk                     ( clk                                               ),
//     .rst_n                   ( rst_n                                             ),
//     .freq_corrected_i        ( freq_corrected_i        [SYMBOL_DATA_WIDTH-1:0]   ),
//     .freq_corrected_q        ( freq_corrected_q        [SYMBOL_DATA_WIDTH-1:0]   ),
//     .freq_corrected_strobe   ( freq_corrected_strobe                             ),
//     .preamble_aligned_start  ( preamble_aligned_start                            ),

//     .data_for_demod_start    ( data_for_demod_start                              ),
//     .data_for_demod_strobe   ( data_for_demod_strobe                             ),
//     .data_for_demod_i        ( data_for_demod_i        [2*SYMBOL_DATA_WIDTH-1:0] ),
//     .data_for_demod_q        ( data_for_demod_q        [2*SYMBOL_DATA_WIDTH-1:0] )
// );
endmodule