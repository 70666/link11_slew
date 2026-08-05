module link11_slew_step5 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 16
) (
    input wire clk,
    input wire rst_n,
    input wire                  preamble_aligned_envelope   ,
    input wire                  preamble_aligned_start      ,
    input wire [LPF_WIDTH-1:0]  preamble_aligned_i          ,
    input wire [LPF_WIDTH-1:0]  preamble_aligned_q          ,
    input wire                  preamble_aligned_probe      ,
    output wire                                        data_for_demod_start ,  
    output wire                                        data_for_demod_strobe,  
    output wire [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] data_for_demod_i     ,  
    output wire [2*(LPF_WIDTH+$clog2(WINDOW_NUM))-1:0] data_for_demod_q     ,
    output wire envelope_for_demod  
);


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
wire                        symbol_envelope;
link11_slew_step5_samples_to_symbol #(
    .LPF_WIDTH                 ( LPF_WIDTH                 ),
    .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
    .ADDER_IMPL_TYPE           ( "DSP"                      ),
    .ADDER_LATENCY             ( ADDER_LATENCY             ),
    .WINDOW_NUM_WIDTH          ( WINDOW_NUM_WIDTH          ),
    .WINDOW_NUM                ( WINDOW_NUM                ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ))
 u_link11_slew_step5_samples_to_symbol (
    .clk                        ( clk                                                ),
    .rst_n                      ( rst_n                                              ),
    .preamble_aligned_envelope  ( preamble_aligned_envelope                          ),
    .preamble_aligned_start     ( preamble_aligned_start                             ),
    .preamble_aligned_i         ( preamble_aligned_i         [LPF_WIDTH-1:0]         ),
    .preamble_aligned_q         ( preamble_aligned_q         [LPF_WIDTH-1:0]         ),
    .preamble_aligned_probe     ( preamble_aligned_probe                             ),

    .symbol_strobe              ( symbol_strobe                                      ),
    .symbol_i                   ( symbol_i                   [SYMBOL_DATA_WIDTH-1:0] ),
    .symbol_q                   ( symbol_q                   [SYMBOL_DATA_WIDTH-1:0] ),
    .symbol_envelope            ( symbol_envelope                                    )
);


wire                        preamble_derot_strobe;
wire [DEROT_DATA_WIDTH-1:0] preamble_derot_i     ;
wire [DEROT_DATA_WIDTH-1:0] preamble_derot_q     ;
link11_slew_step5_derot #(
    .SYMBOL_DATA_WIDTH         ( SYMBOL_DATA_WIDTH         ),
    .DEROT_DATA_WIDTH          ( DEROT_DATA_WIDTH          ),
    .KNOWN_SEQUENCE_END_SYMBOL ( KNOWN_SEQUENCE_END_SYMBOL ),
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
    .symbol_envelope            ( symbol_envelope                                      ),
    .preamble_derot_i           ( preamble_derot_i           [DEROT_DATA_WIDTH-1:0]    ),
    .preamble_derot_q           ( preamble_derot_q           [DEROT_DATA_WIDTH-1:0]    ),
    .preamble_derot_strobe      ( preamble_derot_strobe                                ),

    .data_for_demod_start       ( data_for_demod_start                                 ),
    .data_for_demod_strobe      ( data_for_demod_strobe                                ),
    .data_for_demod_i           ( data_for_demod_i           [2*SYMBOL_DATA_WIDTH-1:0] ),
    .data_for_demod_q           ( data_for_demod_q           [2*SYMBOL_DATA_WIDTH-1:0] ),
    .envelope_for_demod         ( envelope_for_demod                                   )
);

endmodule