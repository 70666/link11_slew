module link11_slew_simulate (
);

// tx param
localparam SAMPLE_CLK_NUM = 32;
localparam SYMBOL_SAMPLE_NUM = 64;
localparam real CARRIER_FREQ_OFFSET_HZ = 15.0;
localparam AMPLITUDE = 20000;
localparam NOISE_STDDEV = 1000;
localparam NOISE_SEED = 1;
localparam MULTIPATH_ENABLE = 1'b0;
localparam MULTIPATH_DELAY_SAMPLES = 4;
localparam real MULTIPATH_GAIN = 0.25;
localparam real MULTIPATH_PHASE_DEG = 30.0;
localparam DATA_BLOCK_NUM = 5;
// rx param
localparam DATA_WIDTH = 16;
localparam WINDOW_NUM = SYMBOL_SAMPLE_NUM;
localparam STANDARD_1800_PHASE_INC = ((1800*65536) / (2400*SYMBOL_SAMPLE_NUM));

reg clk = 0;
always #5 
    clk = ~clk;

reg rst_n = 0;
reg start = 0;
initial begin
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(10) @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;
end





wire iq_strobe;
wire [15:0] tx_i, tx_q;
wire [15:0] tx_zero_if_i, tx_zero_if_q;

wire [1:0] tx_raw_dibit;    
wire [2:0] tx_raw_phase;
wire tx_raw_dibit_strobe;       
wire [7:0] tx_scramble_idx;
wire [2:0] tx_scramble_sym;
wire [2:0] tx_symbol_phase;

wire [31:0] envelope_detection = 18000;

localparam [32:0] HEADER_RAW_PAYLOAD = 33'b10110_01101_11000_10101_00110_11100_100;
localparam [DATA_BLOCK_NUM*48-1:0] DATA_RAW_PAYLOAD = {DATA_BLOCK_NUM{48'h1234_5678_9ABC}};
link11_slew_tx_top_sim #(
    .SAMPLE_CLK_NUM    ( SAMPLE_CLK_NUM    ),
    .SYMBOL_SAMPLE_NUM ( SYMBOL_SAMPLE_NUM ),
    .CARRIER_FREQ_OFFSET_HZ ( CARRIER_FREQ_OFFSET_HZ ),
    .AMPLITUDE         ( AMPLITUDE         ),
    .NOISE_STDDEV      ( NOISE_STDDEV      ),
    .NOISE_SEED        ( NOISE_SEED        ),
    .MULTIPATH_ENABLE  ( MULTIPATH_ENABLE  ),
    .MULTIPATH_DELAY_SAMPLES ( MULTIPATH_DELAY_SAMPLES ),
    .MULTIPATH_GAIN    ( MULTIPATH_GAIN    ),
    .MULTIPATH_PHASE_DEG ( MULTIPATH_PHASE_DEG ),
    .DATA_BLOCK_NUM    ( DATA_BLOCK_NUM    ),
    .HEADER_RAW_PAYLOAD ( HEADER_RAW_PAYLOAD ),
    .DATA_RAW_PAYLOAD   ( DATA_RAW_PAYLOAD   ),
    .EOF_ALL_ONES       ( 1'b0               ))
 u_link11_slew_tx_top_sim (
    .clk                     ( clk                   ),
    .rst_n                   ( rst_n                 ),
    .start                   ( start                 ),

    .busy                    ( busy                  ),
    .done                    ( done                  ),
    .iq_strobe               ( iq_strobe             ),
    .symbol_strobe           ( symbol_strobe         ),
    .tx_raw_dibit            ( tx_raw_dibit         [1:0]  ),
    .tx_raw_phase            ( tx_raw_phase         [2:0]  ),
    .tx_raw_dibit_strobe     ( tx_raw_dibit_strobe         ),
    .tx_scramble_idx         ( tx_scramble_idx      [7:0]  ),
    .tx_scramble_sym         ( tx_scramble_sym      [2:0]  ),
    .tx_symbol_phase         ( tx_symbol_phase      [2:0]  ),
    .tx_zero_if_i            ( tx_zero_if_i        [15:0]  ),
    .tx_zero_if_q            ( tx_zero_if_q        [15:0]  ),
    .tx_i                    ( tx_i           [15:0] ),
    .tx_q                    ( tx_q           [15:0] )
);

wire        viterbi_done     ;  
wire [59:0] decoded_bits     ;  
wire [5:0]  decoded_length   ;  
wire [5:0]  best_start_state ;  
wire [7:0]  best_path_metric ;  
wire        crc_check_pass   ;  
wire        crc_check_strobe ;  
link11_slew_demod_top #(
    .DATA_WIDTH              ( DATA_WIDTH              ),
    .WINDOW_NUM              ( WINDOW_NUM              ),
    .STANDARD_1800_PHASE_INC ( STANDARD_1800_PHASE_INC ))
 u_link11_slew_demod_top (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .device_type             ( device_type                            ),
    .signal_if_strobe        ( iq_strobe                       ),
    .signal_if_i             ( tx_i         [DATA_WIDTH-1:0]   ),
    .signal_if_q             ( tx_q         [DATA_WIDTH-1:0]   ),
    .envelope_detection      ( envelope_detection  [2*DATA_WIDTH-1:0] ),

    .viterbi_done            ( viterbi_done                           ),
    .decoded_bits            ( decoded_bits        [59:0]             ),
    .decoded_length          ( decoded_length      [5:0]              ),
    .best_start_state        ( best_start_state    [5:0]              ),
    .best_path_metric        ( best_path_metric    [7:0]              ),
    .crc_check_pass          ( crc_check_pass                         ),
    .crc_check_strobe        ( crc_check_strobe                       )
);
endmodule
