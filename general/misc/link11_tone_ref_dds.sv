`timescale 1ns / 1ps
// 延时
// One-tone DDS reference generator.
// Each in_strobe sends the current phase to lut_sin and then advances phase_acc.
module link11_tone_ref_dds #(
    parameter integer DATA_WIDTH = 16,       // sin/cos output width, signed, current legal value is 16.
    parameter integer PHASE_WIDTH = 16,      // DDS phase width, unit is 1/2^PHASE_WIDTH cycle, current legal value is 16.
    parameter [PHASE_WIDTH-1:0] PHASE_INC = 16'd0  // Phase step per valid strobe, unit is phase LSB/strobe.
) (
    input  wire clk,                         // Fabric clock.
    input  wire rst_n,                       // Synchronous active-low reset.
    input  wire clear,                       // One-clock clear pulse for phase reference.
    input  wire in_strobe,                   // Input sample valid pulse.
    output wire ref_strobe,                  // ref_i/q valid pulse, delayed 7 strobes + 1 clock from in_strobe.
    output wire [DATA_WIDTH-1:0] ref_i,      // Tone cosine reference, signed.
    output wire [DATA_WIDTH-1:0] ref_q       // Tone sine reference, signed.
);

    localparam integer REF_LATENCY_STROBE = 7;
    localparam integer REF_LATENCY_CLK = 1;

    reg [PHASE_WIDTH-1:0] phase_acc;
    wire [DATA_WIDTH-1:0] unused_sin_preload [0:0];
    wire [DATA_WIDTH-1:0] unused_cos_preload [0:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_acc <= {PHASE_WIDTH{1'b0}};
        end else if (clear) begin
            if (in_strobe) begin
                phase_acc <= PHASE_INC;
            end else begin
                phase_acc <= {PHASE_WIDTH{1'b0}};
            end
        end else if (in_strobe) begin
            phase_acc <= phase_acc + PHASE_INC;
        end
    end

    // 这里的延时是7个strobe延时 + 1个输入寄存器延时
    // 也就是说ref_strobe相对于in_strobe只有一个clk延时, 对应的索引输出相对于索引输入有7个strobe延时
    lut_sin #(
        .WORKING_MODE   ( "RUNTIME"  ),
        .PHASE_WIDTH    ( PHASE_WIDTH ),
        .DATA_WIDTH     ( DATA_WIDTH  ),
        .PRELOAD_LENGTH ( 1           ))
    u_lut_sin_ref (
        .clk          ( clk                ),
        .rst_n        ( rst_n              ),
        .phase_strobe ( in_strobe          ),
        .phase        ( phase_acc          ),
        .data_strobe  ( ref_strobe         ),
        .sin          ( ref_q              ),
        .cos          ( ref_i              ),
        .sin_preload  ( unused_sin_preload ),
        .cos_preload  ( unused_cos_preload )
    );

endmodule
