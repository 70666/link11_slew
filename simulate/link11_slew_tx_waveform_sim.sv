`timescale 1ns / 1ps

// Link-11 SLEW transmit waveform model for receiver simulation.
// SAMPLE_CLK_NUM clocks generate one IQ sample, and SYMBOL_SAMPLE_NUM samples generate one symbol.
// SLEW carrier is 1800 Hz at 2400 Bd, so carrier phase advances 3/4 cycle per symbol.
module link11_slew_tx_waveform_sim #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 1,
    parameter real CARRIER_FREQ_OFFSET_HZ = 0.0,
    parameter signed [15:0] AMPLITUDE = 16'sd16384,
    parameter integer NOISE_STDDEV = 0,              // Per-I/Q Gaussian standard deviation in output LSBs.
    parameter integer NOISE_SEED = 1,                 // Deterministic noise sequence seed.
    parameter MULTIPATH_ENABLE = 1'b0,
    parameter integer MULTIPATH_DELAY_SAMPLES = 4,    // Must be at least 1 IQ sample.
    parameter real MULTIPATH_GAIN = 0.25,
    parameter real MULTIPATH_PHASE_DEG = 45.0
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
    localparam real MULTIPATH_PHASE_RAD = MULTIPATH_PHASE_DEG * PI / 180.0;

    reg [SAMPLE_CLK_CNT_WIDTH-1:0] sample_clk_cnt;
    reg [SYMBOL_SAMPLE_CNT_WIDTH-1:0] symbol_sample_cnt;
    reg [2:0] active_symbol_phase;
    // One delayed complex path is added to the direct path when enabled.
    reg signed [15:0] multipath_i_history [0:MULTIPATH_DELAY_SAMPLES-1];
    reg signed [15:0] multipath_q_history [0:MULTIPATH_DELAY_SAMPLES-1];
    real carrier_phase;
    integer noise_seed;
    integer delay_index;
    integer noise_i_sample;
    integer noise_q_sample;
    reg signed [15:0] direct_i_sample;
    reg signed [15:0] direct_q_sample;
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

    function automatic signed [15:0] saturate16;
        input integer value;
        begin
            if (value > 32767) begin
                saturate16 = 16'sd32767;
            end else if (value < -32768) begin
                saturate16 = -16'sd32768;
            end else begin
                saturate16 = value;
            end
        end
    endfunction

    function automatic signed [15:0] apply_channel_i;
        input signed [15:0] source_i;
        input signed [15:0] delayed_i;
        input signed [15:0] delayed_q;
        input integer noise_i;
        real channel_i;
        begin
            channel_i = source_i + noise_i;
            if (MULTIPATH_ENABLE) begin
                channel_i = channel_i + MULTIPATH_GAIN *
                            (delayed_i * $cos(MULTIPATH_PHASE_RAD) - delayed_q * $sin(MULTIPATH_PHASE_RAD));
            end
            apply_channel_i = saturate16($rtoi(channel_i));
        end
    endfunction

    function automatic signed [15:0] apply_channel_q;
        input signed [15:0] source_q;
        input signed [15:0] delayed_i;
        input signed [15:0] delayed_q;
        input integer noise_q;
        real channel_q;
        begin
            channel_q = source_q + noise_q;
            if (MULTIPATH_ENABLE) begin
                channel_q = channel_q + MULTIPATH_GAIN *
                            (delayed_i * $sin(MULTIPATH_PHASE_RAD) + delayed_q * $cos(MULTIPATH_PHASE_RAD));
            end
            apply_channel_q = saturate16($rtoi(channel_q));
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_clk_cnt <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'd0;
            carrier_phase <= 0.0;
            noise_seed <= NOISE_SEED;
            for (delay_index = 0; delay_index < MULTIPATH_DELAY_SAMPLES; delay_index = delay_index + 1) begin
                multipath_i_history[delay_index] <= 16'sd0;
                multipath_q_history[delay_index] <= 16'sd0;
            end
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
            noise_seed <= NOISE_SEED;
            for (delay_index = 0; delay_index < MULTIPATH_DELAY_SAMPLES; delay_index = delay_index + 1) begin
                multipath_i_history[delay_index] <= 16'sd0;
                multipath_q_history[delay_index] <= 16'sd0;
            end
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
                    direct_i_sample = phase_to_i(symbol_phase, carrier_phase);
                    direct_q_sample = phase_to_q(symbol_phase, carrier_phase);
                    noise_i_sample = (NOISE_STDDEV == 0) ? 0 : $dist_normal(noise_seed, 0, NOISE_STDDEV);
                    noise_q_sample = (NOISE_STDDEV == 0) ? 0 : $dist_normal(noise_seed, 0, NOISE_STDDEV);
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
                    tx_i <= apply_channel_i(direct_i_sample, multipath_i_history[MULTIPATH_DELAY_SAMPLES-1], multipath_q_history[MULTIPATH_DELAY_SAMPLES-1], noise_i_sample);
                    tx_q <= apply_channel_q(direct_q_sample, multipath_i_history[MULTIPATH_DELAY_SAMPLES-1], multipath_q_history[MULTIPATH_DELAY_SAMPLES-1], noise_q_sample);
                end else begin
                    direct_i_sample = phase_to_i(active_symbol_phase, carrier_phase);
                    direct_q_sample = phase_to_q(active_symbol_phase, carrier_phase);
                    noise_i_sample = (NOISE_STDDEV == 0) ? 0 : $dist_normal(noise_seed, 0, NOISE_STDDEV);
                    noise_q_sample = (NOISE_STDDEV == 0) ? 0 : $dist_normal(noise_seed, 0, NOISE_STDDEV);
                    symbol_strobe <= 1'b0;
                    tx_raw_dibit_strobe <= 1'b0;
                    tx_zero_if_i <= phase_to_i(active_symbol_phase, 0.0);
                    tx_zero_if_q <= phase_to_q(active_symbol_phase, 0.0);
                    tx_i <= apply_channel_i(direct_i_sample, multipath_i_history[MULTIPATH_DELAY_SAMPLES-1], multipath_q_history[MULTIPATH_DELAY_SAMPLES-1], noise_i_sample);
                    tx_q <= apply_channel_q(direct_q_sample, multipath_i_history[MULTIPATH_DELAY_SAMPLES-1], multipath_q_history[MULTIPATH_DELAY_SAMPLES-1], noise_q_sample);
                end
                for (delay_index = MULTIPATH_DELAY_SAMPLES - 1; delay_index > 0; delay_index = delay_index - 1) begin
                    multipath_i_history[delay_index] <= multipath_i_history[delay_index-1];
                    multipath_q_history[delay_index] <= multipath_q_history[delay_index-1];
                end
                multipath_i_history[0] <= direct_i_sample;
                multipath_q_history[0] <= direct_q_sample;
            end else begin
                symbol_strobe <= 1'b0;
                tx_raw_dibit_strobe <= 1'b0;
                symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
                active_symbol_phase <= 3'd0;
                tx_zero_if_i <= 16'sd0;
                tx_zero_if_q <= 16'sd0;
                tx_i <= 16'sd0;
                tx_q <= 16'sd0;
                for (delay_index = 0; delay_index < MULTIPATH_DELAY_SAMPLES; delay_index = delay_index + 1) begin
                    multipath_i_history[delay_index] <= 16'sd0;
                    multipath_q_history[delay_index] <= 16'sd0;
                end
            end
        end else begin
            sample_clk_cnt <= sample_clk_cnt + 1'b1;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
            tx_raw_dibit_strobe <= 1'b0;
        end
    end

endmodule
