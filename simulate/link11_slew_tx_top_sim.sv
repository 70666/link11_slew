`timescale 1ns / 1ps

// Link-11 SLEW transmit simulation top.
// Header/data parameters contain uncoded information bits. MSB is transmitted first.
module link11_slew_tx_top_sim #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 1,
    parameter real CARRIER_FREQ_OFFSET_HZ = 0.0,
    parameter signed [15:0] AMPLITUDE = 16'sd16384,
    parameter integer DATA_BLOCK_NUM = 1,
    parameter [32:0] HEADER_RAW_PAYLOAD = 33'b0,
    parameter [DATA_BLOCK_NUM*48-1:0] DATA_RAW_PAYLOAD = {DATA_BLOCK_NUM*48{1'b0}},
    parameter EOF_ALL_ONES = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    output wire        busy,
    output wire        done,
    output wire        iq_strobe,
    output wire        symbol_strobe,
    output wire [1:0]  tx_raw_dibit,
    output wire [2:0]  tx_raw_phase,
    output wire        tx_raw_dibit_strobe,
    output wire [7:0]  tx_scramble_idx,
    output wire [2:0]  tx_scramble_sym,
    output wire [2:0]  tx_symbol_phase,
    output wire signed [15:0] tx_zero_if_i,
    output wire signed [15:0] tx_zero_if_q,
    output wire signed [15:0] tx_i,
    output wire signed [15:0] tx_q
);

    wire [2:0] waveform_symbol_phase;
    wire       tx_symbol_take;
    wire [1:0] digital_raw_dibit;
    wire [2:0] digital_raw_phase;
    wire       digital_raw_valid;
    wire [7:0] digital_scramble_idx;
    wire [2:0] digital_scramble_sym;
    wire [2:0] digital_symbol_phase;
    reg        waveform_enable;

    always @(posedge clk) begin
        if (!rst_n) begin
            waveform_enable <= 1'b0;
        end else if (start) begin
            waveform_enable <= 1'b1;
        end
    end

    link11_slew_tx_digital_sim #(
        .DATA_BLOCK_NUM    ( DATA_BLOCK_NUM    ),
        .HEADER_RAW_PAYLOAD ( HEADER_RAW_PAYLOAD ),
        .DATA_RAW_PAYLOAD   ( DATA_RAW_PAYLOAD   ),
        .EOF_ALL_ONES       ( EOF_ALL_ONES       ))
    u_tx_digital (
        .clk                       ( clk                       ),
        .rst_n                     ( rst_n                     ),
        .start                     ( start                     ),
        .symbol_take               ( tx_symbol_take            ),
        .symbol_phase              ( waveform_symbol_phase     ),
        .tx_raw_dibit              ( digital_raw_dibit         ),
        .tx_raw_phase              ( digital_raw_phase         ),
        .tx_raw_dibit_strobe       ( digital_raw_valid         ),
        .tx_scramble_idx           ( digital_scramble_idx      ),
        .tx_scramble_sym           ( digital_scramble_sym      ),
        .tx_symbol_phase           ( digital_symbol_phase      ),
        .busy                      ( busy                      ),
        .done                      ( done                      )
    );

    // Waveform latency: one IQ strobe per SAMPLE_CLK_NUM clocks, one symbol per SYMBOL_SAMPLE_NUM samples.
    link11_slew_tx_waveform_sim #(
        .SAMPLE_CLK_NUM    ( SAMPLE_CLK_NUM    ),
        .SYMBOL_SAMPLE_NUM ( SYMBOL_SAMPLE_NUM ),
        .CARRIER_FREQ_OFFSET_HZ ( CARRIER_FREQ_OFFSET_HZ ),
        .AMPLITUDE         ( AMPLITUDE         ))
    u_tx_waveform (
        .clk              ( clk              ),
        .rst_n            ( rst_n            ),
        .enable           ( waveform_enable  ),
        .symbol_enable    ( busy             ),
        .symbol_phase     ( waveform_symbol_phase ),
        .debug_raw_dibit  ( digital_raw_dibit ),
        .debug_raw_phase  ( digital_raw_phase ),
        .debug_raw_valid  ( digital_raw_valid ),
        .debug_scramble_idx ( digital_scramble_idx ),
        .debug_scramble_sym ( digital_scramble_sym ),
        .debug_symbol_phase ( digital_symbol_phase ),
        .symbol_ready     ( tx_symbol_take   ),
        .iq_strobe        ( iq_strobe        ),
        .symbol_strobe    ( symbol_strobe    ),
        .tx_raw_dibit     ( tx_raw_dibit     ),
        .tx_raw_phase     ( tx_raw_phase     ),
        .tx_raw_dibit_strobe ( tx_raw_dibit_strobe ),
        .tx_scramble_idx  ( tx_scramble_idx  ),
        .tx_scramble_sym  ( tx_scramble_sym  ),
        .tx_symbol_phase  ( tx_symbol_phase  ),
        .tx_zero_if_i     ( tx_zero_if_i     ),
        .tx_zero_if_q     ( tx_zero_if_q     ),
        .tx_i             ( tx_i             ),
        .tx_q             ( tx_q             )
    );

endmodule
