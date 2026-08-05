`timescale 1ns / 1ps

// 可综合的 Link-11 SLEW 发射顶层, 仅连接数字域和波形域.
module link11_slew_tx #(
    // 每个 IQ 采样点占用的输入时钟数.
    parameter integer SAMPLE_CLK_NUM = 1,
    // 每个 2400 Baud symbol 包含的 IQ 采样点数.
    parameter integer SYMBOL_SAMPLE_NUM = 32,
    // 16-bit DDS 步进, 计算式为 round(1800/(2400*SYMBOL_SAMPLE_NUM)*65536).
    parameter [15:0] CARRIER_PHASE_INC = 16'd1536
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_tx,
    input  wire        raw_data_valid,
    input  wire [3:0]  raw_data_index,
    input  wire [47:0] raw_data,
    input  wire [3:0]  data_block_num,
    input  wire [15:0] amplitude,
    input  wire        eof_bit,

    output wire               busy,
    output wire               done,
    output wire               tx_enable,
    output wire               tx_strobe,
    output wire signed [15:0] tx_i,
    output wire signed [15:0] tx_q
);

    wire       symbol_take;
    wire       symbol_valid;
    wire [2:0] symbol_phase;
    wire       digital_busy;
    wire       digital_done;

    // 数字域负责 VIO 数据缓存, CRC/卷积编码, 帧调度, Gray 映射和加扰.
    link11_slew_tx_raw_data u_digital (
        .clk            ( clk            ),
        .rst_n          ( rst_n          ),
        .start_tx       ( start_tx       ),
        .raw_data_valid ( raw_data_valid ),
        .raw_data_index ( raw_data_index ),
        .raw_data       ( raw_data       ),
        .data_block_num ( data_block_num ),
        .eof_bit        ( eof_bit        ),
        .symbol_take    ( symbol_take    ),
        .symbol_valid   ( symbol_valid   ),
        .symbol_phase   ( symbol_phase   ),
        .busy           ( digital_busy   ),
        .done           ( digital_done   )
    );

    // 波形域延时: 1 clk DDS 输入寄存器 + 7 clk DDS IP + 2 clk 幅度乘法器.
    link11_slew_tx_waveform #(
        .SAMPLE_CLK_NUM    ( SAMPLE_CLK_NUM    ),
        .SYMBOL_SAMPLE_NUM ( SYMBOL_SAMPLE_NUM ),
        .CARRIER_PHASE_INC ( CARRIER_PHASE_INC ))
    u_waveform (
        .clk          ( clk          ),
        .rst_n        ( rst_n        ),
        .symbol_valid ( symbol_valid ),
        .symbol_phase ( symbol_phase ),
        .digital_busy ( digital_busy ),
        .digital_done ( digital_done ),
        .amplitude    ( amplitude    ),
        .symbol_take  ( symbol_take  ),
        .busy         ( busy         ),
        .done         ( done         ),
        .tx_enable    ( tx_enable    ),
        .tx_strobe    ( tx_strobe    ),
        .tx_i         ( tx_i         ),
        .tx_q         ( tx_q         )
    );

endmodule
