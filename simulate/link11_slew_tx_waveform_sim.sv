`timescale 1ns / 1ps

// Link-11 SLEW transmit waveform model for receiver simulation.
// SAMPLE_CLK_NUM clocks generate one IQ sample, and SYMBOL_SAMPLE_NUM samples generate one symbol.
// SLEW carrier is 1800 Hz at 2400 Bd, so carrier phase advances 3/4 cycle per symbol.
module link11_slew_tx_waveform_sim #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 1,
    parameter signed [15:0] AMPLITUDE = 16'sd16384
) (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,

    input  wire [2:0]  symbol_phase,
    output reg         symbol_ready,

    output reg         iq_strobe,
    output reg         symbol_strobe,
    output reg signed [15:0] tx_i,
    output reg signed [15:0] tx_q
);

    localparam integer SAMPLE_CLK_CNT_WIDTH = (SAMPLE_CLK_NUM <= 1) ? 1 : $clog2(SAMPLE_CLK_NUM);
    localparam integer SYMBOL_SAMPLE_CNT_WIDTH = (SYMBOL_SAMPLE_NUM <= 1) ? 1 : $clog2(SYMBOL_SAMPLE_NUM);
    localparam real PI = 3.14159265358979323846;
    localparam real TWO_PI = 6.28318530717958647692;
    localparam real CARRIER_PHASE_INC = TWO_PI * 3.0 / (4.0 * SYMBOL_SAMPLE_NUM);

    reg [SAMPLE_CLK_CNT_WIDTH-1:0] sample_clk_cnt;
    reg [SYMBOL_SAMPLE_CNT_WIDTH-1:0] symbol_sample_cnt;
    reg [2:0] active_symbol_phase;
    real carrier_phase;

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
            symbol_ready <= 1'b0;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
            tx_i <= 16'sd0;
            tx_q <= 16'sd0;
        end else if (!enable) begin
            sample_clk_cnt <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'd0;
            carrier_phase <= 0.0;
            symbol_ready <= 1'b0;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
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

            if (symbol_sample_cnt == SYMBOL_SAMPLE_NUM - 1) begin
                symbol_sample_cnt <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            end else begin
                symbol_sample_cnt <= symbol_sample_cnt + 1'b1;
            end

            // symbol_strobe marks the first IQ sample that uses a new input symbol.
            if (symbol_sample_cnt == {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}}) begin
                active_symbol_phase <= symbol_phase;
                symbol_ready <= 1'b1;
                symbol_strobe <= 1'b1;
                tx_i <= phase_to_i(symbol_phase, carrier_phase);
                tx_q <= phase_to_q(symbol_phase, carrier_phase);
            end else begin
                symbol_ready <= 1'b0;
                symbol_strobe <= 1'b0;
                tx_i <= phase_to_i(active_symbol_phase, carrier_phase);
                tx_q <= phase_to_q(active_symbol_phase, carrier_phase);
            end
        end else begin
            sample_clk_cnt <= sample_clk_cnt + 1'b1;
            symbol_ready <= 1'b0;
            iq_strobe <= 1'b0;
            symbol_strobe <= 1'b0;
        end
    end

endmodule
