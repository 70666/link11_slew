`timescale 1ns / 1ps

// 将 3-bit symbol 相位转换为带 1800 Hz 载波的 16-bit IQ 采样.
module link11_slew_tx_waveform #(
    parameter integer SAMPLE_CLK_NUM = 1,
    parameter integer SYMBOL_SAMPLE_NUM = 32,
    parameter [15:0] CARRIER_PHASE_INC = 16'd1536
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       symbol_valid,
    input  wire [2:0] symbol_phase,
    input  wire       digital_busy,
    input  wire       digital_done,
    // 无符号 Q0.16 幅度系数, 16'hFFFF 约等于 1 倍满幅.
    input  wire [15:0] amplitude,

    output wire               symbol_take,
    output wire               busy,
    output wire               done,
    output wire               tx_enable,
    output wire               tx_strobe,
    output wire signed [15:0] tx_i,
    output wire signed [15:0] tx_q
);

    localparam integer SAMPLE_CLK_CNT_WIDTH =
        (SAMPLE_CLK_NUM <= 1) ? 1 : $clog2(SAMPLE_CLK_NUM);
    localparam integer SYMBOL_SAMPLE_CNT_WIDTH =
        (SYMBOL_SAMPLE_NUM <= 1) ? 1 : $clog2(SYMBOL_SAMPLE_NUM);
    localparam integer SCALE_LATENCY_CLK = 2;
    localparam integer DDS_INPUT_LATENCY_CLK = 1;
    localparam integer DDS_CORE_LATENCY_CLK = 7;
    localparam integer TX_OUTPUT_PIPELINE_STAGE_NUM =
        DDS_INPUT_LATENCY_CLK + DDS_CORE_LATENCY_CLK + SCALE_LATENCY_CLK;
    localparam integer DONE_DELAY_REG_NUM =
        TX_OUTPUT_PIPELINE_STAGE_NUM - 1;

    wire sample_tick;
    wire symbol_last_sample;
    wire [2:0] sample_symbol_phase;
    wire [15:0] dds_phase;
    wire dds_strobe;
    wire [15:0] dds_i;
    wire [15:0] dds_q;
    wire [15:0] unused_sin_preload [0:0];
    wire [15:0] unused_cos_preload [0:0];
    wire signed [31:0] scaled_i_full;
    wire signed [31:0] scaled_q_full;

    reg [SAMPLE_CLK_CNT_WIDTH-1:0] sample_clk_count;
    reg [SYMBOL_SAMPLE_CNT_WIDTH-1:0] symbol_sample_count;
    reg [2:0] active_symbol_phase;
    reg [15:0] carrier_phase;
    reg [SCALE_LATENCY_CLK-1:0] scale_strobe_delay;
    reg [DONE_DELAY_REG_NUM-1:0] done_delay;
    reg tx_active;

    assign sample_tick = symbol_valid &&
                         (sample_clk_count == SAMPLE_CLK_NUM - 1);
    assign symbol_last_sample = sample_tick &&
                                (symbol_sample_count == SYMBOL_SAMPLE_NUM - 1);

    // 在 symbol 的最后一个采样点才请求下一个 symbol, 防止末采样被截断.
    assign symbol_take = symbol_last_sample;

    // 每个 symbol 的第一个采样锁存新相位, 其余采样保持该相位.
    assign sample_symbol_phase =
        (symbol_sample_count == {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}}) ?
        symbol_phase : active_symbol_phase;
    assign dds_phase = carrier_phase + {sample_symbol_phase, 13'b0};

    assign tx_strobe = scale_strobe_delay[SCALE_LATENCY_CLK-1];
    assign busy = digital_busy || digital_done || (|done_delay);
    assign done = done_delay[DONE_DELAY_REG_NUM-1];
    // 覆盖第一和最后一个有效采样, 中间无 strobe 的 clk 也持续保持为 1.
    assign tx_enable = tx_active || tx_strobe;

    // 有符号 IQ 乘无符号 Q0.16 系数, 取高 16 bit 等比例缩放.
    assign tx_i = scaled_i_full[31:16];
    assign tx_q = scaled_q_full[31:16];

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_clk_count <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_count <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'b0;
            carrier_phase <= 16'b0;
        end else if (!symbol_valid) begin
            sample_clk_count <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            symbol_sample_count <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            active_symbol_phase <= 3'b0;
            carrier_phase <= 16'b0;
        end else if (sample_tick) begin
            sample_clk_count <= {SAMPLE_CLK_CNT_WIDTH{1'b0}};
            carrier_phase <= carrier_phase + CARRIER_PHASE_INC;
            if (symbol_sample_count == {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}}) begin
                active_symbol_phase <= symbol_phase;
            end
            if (symbol_sample_count == SYMBOL_SAMPLE_NUM - 1) begin
                symbol_sample_count <= {SYMBOL_SAMPLE_CNT_WIDTH{1'b0}};
            end else begin
                symbol_sample_count <= symbol_sample_count + 1'b1;
            end
        end else begin
            sample_clk_count <= sample_clk_count + 1'b1;
        end
    end

    // DDS 延时: 1 clk 输入寄存器 + 7 个有效采样.
    lut_sin #(
        .WORKING_MODE   ( "RUNTIME" ),
        .PHASE_WIDTH    ( 16        ),
        .DATA_WIDTH     ( 16        ),
        .PRELOAD_LENGTH ( 1         ))
    u_tx_dds (
        .clk          ( clk                ),
        .rst_n        ( rst_n              ),
        .phase_strobe ( sample_tick        ),
        .phase        ( dds_phase          ),
        .data_strobe  ( dds_strobe         ),
        .sin          ( dds_q              ),
        .cos          ( dds_i              ),
        .sin_preload  ( unused_sin_preload ),
        .cos_preload  ( unused_cos_preload )
    );

    // I 路幅度缩放延时: SCALE_LATENCY_CLK.
    multiplier #(
        .IMPL_TYPE ( "DSP"             ),
        .A_WIDTH   ( 16                ),
        .B_WIDTH   ( 16                ),
        .A_TYPE    ( 1                 ),
        .B_TYPE    ( 0                 ),
        .LATENCY   ( SCALE_LATENCY_CLK ),
        .OUT_WIDTH ( 32                ))
    u_scale_i (
        .clk ( clk           ),
        .A   ( dds_i         ),
        .B   ( amplitude     ),
        .P   ( scaled_i_full )
    );

    // Q 路幅度缩放延时: SCALE_LATENCY_CLK.
    multiplier #(
        .IMPL_TYPE ( "DSP"             ),
        .A_WIDTH   ( 16                ),
        .B_WIDTH   ( 16                ),
        .A_TYPE    ( 1                 ),
        .B_TYPE    ( 0                 ),
        .LATENCY   ( SCALE_LATENCY_CLK ),
        .OUT_WIDTH ( 32                ))
    u_scale_q (
        .clk ( clk           ),
        .A   ( dds_q         ),
        .B   ( amplitude     ),
        .P   ( scaled_q_full )
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            scale_strobe_delay <= {SCALE_LATENCY_CLK{1'b0}};
            done_delay <= {DONE_DELAY_REG_NUM{1'b0}};
            tx_active <= 1'b0;
        end else begin
            scale_strobe_delay <= {
                scale_strobe_delay[SCALE_LATENCY_CLK-2:0],
                dds_strobe
            };
            // digital_done 下一拍可见, 因此完成延时链比 IQ 总流水少一级.
            done_delay <= {
                done_delay[DONE_DELAY_REG_NUM-2:0],
                digital_done
            };
            // done 与最后一个 tx_strobe 同拍, 下一拍关闭外部 IQ 门控.
            if (done) begin
                tx_active <= 1'b0;
            end else if (tx_strobe) begin
                tx_active <= 1'b1;
            end
        end
    end

endmodule
