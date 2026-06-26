module link11_slew_simulate (
);

// tx param
localparam SAMPLE_CLK_NUM = 32;
localparam SYMBOL_SAMPLE_NUM = 32;
localparam AMPLITUDE = 30000;
localparam HEADER_SYMBOL_NUM = 64;
localparam DATA_SYMBOL_NUM = 64;
localparam EOM_SYMBOL_NUM = 64;
localparam DATA_BLOCK_NUM = 1;
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

wire [31:0] envelope_detection = 30000;

localparam [3*HEADER_SYMBOL_NUM-1:0] HEADER_PAYLOAD = {{64{3'o0}}};
localparam [3*DATA_SYMBOL_NUM-1:0] DATA_PAYLOAD = {{64{3'o0}}};
localparam [3*EOM_SYMBOL_NUM-1:0] EOM_PAYLOAD = {{64{3'o0}}};
link11_slew_tx_top_sim #(
    .SAMPLE_CLK_NUM    ( SAMPLE_CLK_NUM    ),
    .SYMBOL_SAMPLE_NUM ( SYMBOL_SAMPLE_NUM ),
    .AMPLITUDE         ( AMPLITUDE         ),
    .HEADER_SYMBOL_NUM ( HEADER_SYMBOL_NUM ),
    .DATA_SYMBOL_NUM   ( DATA_SYMBOL_NUM   ),
    .EOM_SYMBOL_NUM    ( EOM_SYMBOL_NUM    ),
    .DATA_BLOCK_NUM    ( DATA_BLOCK_NUM    ),
    .HEADER_PAYLOAD    ( HEADER_PAYLOAD    ),
    .DATA_PAYLOAD      ( DATA_PAYLOAD      ),
    .EOM_PAYLOAD       ( EOM_PAYLOAD       ))
 u_link11_slew_tx_top_sim (
    .clk                     ( clk                   ),
    .rst_n                   ( rst_n                 ),
    .start                   ( start                 ),

    .busy                    ( busy                  ),
    .done                    ( done                  ),
    .iq_strobe               ( iq_strobe             ),
    .symbol_strobe           ( symbol_strobe         ),
    .tx_i                    ( tx_i           [15:0] ),
    .tx_q                    ( tx_q           [15:0] )
);


link11_slew_demod_top #(
    .DATA_WIDTH              ( DATA_WIDTH              ),
    .WINDOW_NUM              ( WINDOW_NUM              ),
    .STANDARD_1800_PHASE_INC ( STANDARD_1800_PHASE_INC ))
 u_link11_slew_demod_top (
    .clk                     ( clk                  ),
    .rst_n                   ( rst_n                ),
    .signal_if_strobe        ( iq_strobe            ),
    .signal_if_i             ( tx_i                 ),
    .signal_if_q             ( tx_q                 ),
    .envelope_detection      ( envelope_detection   )
);


endmodule