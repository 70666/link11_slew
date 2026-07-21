`timescale 1ns / 1ps

// Link-11 SLEW transmit waveform model for receiver simulation.
// SAMPLE_CLK_NUM clocks generate one IQ sample, and SYMBOL_SAMPLE_NUM samples generate one symbol.
// SLEW carrier is 1800 Hz at 2400 Bd, so carrier phase advances 3/4 cycle per symbol.
module link11_slew_tx_waveform_sim #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 1,
    parameter real CARRIER_FREQ_OFFSET_HZ = 0.0,
    parameter signed [15:0] AMPLITUDE = 16'sd16384
) (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire symbol_enable,

    input  wire [2:0]  symbol_phase,
    input  wire [1:0]  debug_raw_dibit,
    input  wire [2:0]  debug_raw_phase,
    input  wire        debug_raw_valid,
    input  wire [7:0]  debug_scramble_idx,
    input  wire [2:0]  debug_scramble_sym,
    input  wire [2:0]  debug_symbol_phase,
    output wire        symbol_ready,

    output reg         iq_strobe,
    output reg         symbol_strobe,
    output reg [1:0]   tx_raw_dibit,
    output reg [2:0]   tx_raw_phase,
    output reg         tx_raw_dibit_strobe,
    output reg [7:0]   tx_scramble_idx,
    output reg [2:0]   tx_scramble_sym,
    output reg [2:0]   tx_symbol_phase,
    output reg signed [15:0] tx_zero_if_i,
    output reg signed [15:0] tx_zero_if_q,
    output reg signed [15:0] tx_i,
    output reg signed [15:0] tx_q
);

    localparam integer SAMPLE_CLK_CNT_WIDTH = (SAMPLE_CLK_NUM <= 1) ? 1 : $clog2(SAMPLE_CLK_NUM);
    localparam integer SYMBOL_SAMPLE_CNT_WIDTH = (SYMBOL_SAMPLE_NUM <= 1) ? 1 : $clog2(SYMBOL_SAMPLE_NUM);
    localparam real PI = 3.14159265358979323846;
    localparam real TWO_PI = 6.28318530717958647692;
    localparam real SYMBOL_RATE_HZ = 2400.0;
    localparam real CARRIER_HZ = 1800.0 + CARRIER_FREQ_OFFSET_HZ;
    localparam real CARRIER_PHASE_INC = TWO_PI * CARRIER_HZ / (SYMBOL_RATE_HZ * SYMBOL_SAMPLE_NUM);

    reg [SAMPLE_CLK_CNT_WIDTH-1:0] sample_clk_cnt;
    reg [SYMBOL_SAMPLE_CNT_WIDTH-1:0] symbol_sample_cnt;
    reg [2:0] active_symbol_phase;
    real carrier_phase;
    wire sample_tick;
    wire symbol_first_sample;

    assign sample_tick = enable && (sample_clk_cnt == SAMPLE_CLK_NUM - 1);
    assign symbol_first_sample = sample_tick && symbol_enable &&
                                 (symbol_sample_cnt == {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}});
    assign symbol_ready = symbol_first_sample;

    function automatic signed [15:0] phase_to_i;
        input [2:0] phase;
        input real carrier_phase_in;
        begin
            phase_to_i = $rtoi($cos(carrier_phase_in + phase * PI / 4.0) * AMPLITUDE);
        end
    endfunction

    function automatic signed [15:0] phase_to_q;
        input [2:0] phase;
        input real carrier_phase_in;
        begin
            phase_to_q = $rtoi($sin(carrier_phase_in + phase * PI / 4.0) * AMPLITUDE);
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_clk_cnt <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'd0;
            carrier_phase <= 0.0;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
            tx_raw_dibit <= 2'b00;
            tx_raw_phase <= 3'd0;
            tx_raw_dibit_strobe <= 1'b0;
            tx_scramble_idx <= 8'd0;
            tx_scramble_sym <= 3'd0;
            tx_symbol_phase <= 3'd0;
            tx_zero_if_i <= 16'sd0;
            tx_zero_if_q <= 16'sd0;
            tx_i <= 16'sd0;
            tx_q <= 16'sd0;
        end else if (!enable) begin
            sample_clk_cnt <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'd0;
            carrier_phase <= 0.0;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
            tx_raw_dibit <= 2'b00;
            tx_raw_phase <= 3'd0;
            tx_raw_dibit_strobe <= 1'b0;
            tx_scramble_idx <= 8'd0;
            tx_scramble_sym <= 3'd0;
            tx_symbol_phase <= 3'd0;
            tx_zero_if_i <= 16'sd0;
            tx_zero_if_q <= 16'sd0;
            tx_i <= 16'sd0;
            tx_q <= 16'sd0;
        end else if (sample_clk_cnt == SAMPLE_CLK_NUM - 1) begin
            sample_clk_cnt <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            iq_strobe <= 1'b1;
            if (carrier_phase >= TWO_PI - CARRIER_PHASE_INC) begin
                carrier_phase <= carrier_phase + CARRIER_PHASE_INC - TWO_PI;
            end else begin
                carrier_phase <= carrier_phase + CARRIER_PHASE_INC;
            end

            if (symbol_enable) begin
                if (symbol_sample_cnt == SYMBOL_SAMPLE_NUM - 1) begin
                    symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
                end else begin
                    symbol_sample_cnt <= symbol_sample_cnt + 1'b1;
                end

                // symbol_strobe marks the first IQ sample that uses a new input symbol.
                if (symbol_sample_cnt == {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}}) begin
                    active_symbol_phase <= symbol_phase;
                    symbol_strobe <= 1'b1;
                    tx_raw_dibit <= debug_raw_dibit;
                    tx_raw_phase <= debug_raw_phase;
                    tx_raw_dibit_strobe <= debug_raw_valid;
                    tx_scramble_idx <= debug_scramble_idx;
                    tx_scramble_sym <= debug_scramble_sym;
                    tx_symbol_phase <= debug_symbol_phase;
                    tx_zero_if_i <= phase_to_i(symbol_phase, 0.0);
                    tx_zero_if_q <= phase_to_q(symbol_phase, 0.0);
                    tx_i <= phase_to_i(symbol_phase, carrier_phase);
                    tx_q <= phase_to_q(symbol_phase, carrier_phase);
                end else begin
                    symbol_strobe <= 1'b0;
                    tx_raw_dibit_strobe <= 1'b0;
                    tx_zero_if_i <= phase_to_i(active_symbol_phase, 0.0);
                    tx_zero_if_q <= phase_to_q(active_symbol_phase, 0.0);
                    tx_i <= phase_to_i(active_symbol_phase, carrier_phase);
                    tx_q <= phase_to_q(active_symbol_phase, carrier_phase);
                end
            end else begin
                symbol_strobe <= 1'b0;
                tx_raw_dibit_strobe <= 1'b0;
                symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
                active_symbol_phase <= 3'd0;
                tx_zero_if_i <= 16'sd0;
                tx_zero_if_q <= 16'sd0;
                tx_i <= 16'sd0;
                tx_q <= 16'sd0;
            end
        end else begin
            sample_clk_cnt <= sample_clk_cnt + 1'b1;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
            tx_raw_dibit_strobe <= 1'b0;
        end
    end

endmodule
