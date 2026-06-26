`timescale 1ns / 1ps

// Link-11 SLEW transmit simulation top.
// Header, data, and EOM contents are supplied by *_PAYLOAD parameters.
module link11_slew_tx_top_sim #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 1,
    parameter signed [15:0] AMPLITUDE = 16'sd16384,
    parameter integer HEADER_SYMBOL_NUM = 30,
    parameter integer DATA_SYMBOL_NUM = 30,
    parameter integer EOM_SYMBOL_NUM = 30,
    parameter integer DATA_BLOCK_NUM = 1,
    localparam DATA_TOTAL_SYMBOL_NUM = DATA_SYMBOL_NUM * DATA_BLOCK_NUM,
    parameter [HEADER_SYMBOL_NUM*3-1:0] HEADER_PAYLOAD = {HEADER_SYMBOL_NUM{3'd0}},
    parameter [DATA_TOTAL_SYMBOL_NUM*3-1:0] DATA_PAYLOAD = {DATA_TOTAL_SYMBOL_NUM{3'd0}},
    parameter [EOM_SYMBOL_NUM*3-1:0] EOM_PAYLOAD = {EOM_SYMBOL_NUM{3'd4}}
) (
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    output wire        busy,
    output wire        done,
    output wire        iq_strobe,
    output wire        symbol_strobe,
    output wire signed [15:0] tx_i,
    output wire signed [15:0] tx_q
);

    wire [2:0] tx_symbol_phase;
    wire       tx_symbol_take;

    link11_slew_tx_digital_sim #(
        .HEADER_SYMBOL_NUM ( HEADER_SYMBOL_NUM ),
        .DATA_SYMBOL_NUM   ( DATA_SYMBOL_NUM   ),
        .EOM_SYMBOL_NUM    ( EOM_SYMBOL_NUM    ),
        .DATA_BLOCK_NUM    ( DATA_BLOCK_NUM    ),
        .DATA_TOTAL_SYMBOL_NUM ( DATA_TOTAL_SYMBOL_NUM ),
        .HEADER_PAYLOAD    ( HEADER_PAYLOAD    ),
        .DATA_PAYLOAD      ( DATA_PAYLOAD      ),
        .EOM_PAYLOAD       ( EOM_PAYLOAD       ))
    u_tx_digital (
        .clk                       ( clk                       ),
        .rst_n                     ( rst_n                     ),
        .start                     ( start                     ),
        .symbol_take               ( tx_symbol_take            ),
        .symbol_phase              ( tx_symbol_phase           ),
        .busy                      ( busy                      ),
        .done                      ( done                      )
    );

    // Waveform latency: one IQ strobe per SAMPLE_CLK_NUM clocks, one symbol per SYMBOL_SAMPLE_NUM samples.
    link11_slew_tx_waveform_sim #(
        .SAMPLE_CLK_NUM    ( SAMPLE_CLK_NUM    ),
        .SYMBOL_SAMPLE_NUM ( SYMBOL_SAMPLE_NUM ),
        .AMPLITUDE         ( AMPLITUDE         ))
    u_tx_waveform (
        .clk              ( clk              ),
        .rst_n            ( rst_n            ),
        .enable           ( busy             ),
        .symbol_phase     ( tx_symbol_phase  ),
        .symbol_ready     ( tx_symbol_take   ),
        .iq_strobe        ( iq_strobe        ),
        .symbol_strobe    ( symbol_strobe    ),
        .tx_i             ( tx_i             ),
        .tx_q             ( tx_q             )
    );

endmodule
