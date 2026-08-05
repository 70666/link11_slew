`timescale 1ns / 1ps

// 数字域顶层, 将帧构建结果交给 symbol 调度器.
module link11_slew_tx_raw_data (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_tx,
    input  wire        raw_data_valid,
    input  wire [3:0]  raw_data_index,
    input  wire [47:0] raw_data,
    input  wire [3:0]  data_block_num,
    input  wire        eof_bit,
    input  wire        symbol_take,

    output wire       symbol_valid,
    output wire [2:0] symbol_phase,
    output wire       busy,
    output wire       done
);

    wire        frame_ready;
    wire        builder_busy;
    wire [3:0]  frame_data_block_num;
    wire        frame_eof_bit;
    wire [89:0] header_coded_bits;
    wire [89:0] data_coded_bits [0:14];
    wire        scheduler_busy;

    // 帧构建延时: header 为 80 clk, 每个 data block 为 110 clk.
    // 这个模块将原始数据拼成一个完整帧, 然后将整帧数字编码交给symbol_scheduler
    link11_slew_tx_frame_builder u_frame_builder (
        .clk                  ( clk                  ),
        .rst_n                ( rst_n                ),
        .start_tx             ( start_tx             ),
        .raw_data_valid       ( raw_data_valid       ),
        .raw_data_index       ( raw_data_index       ),
        .raw_data             ( raw_data             ),
        .data_block_num       ( data_block_num       ),
        .eof_bit              ( eof_bit              ),
        .frame_ready          ( frame_ready          ),
        .busy                 ( builder_busy          ),
        .frame_data_block_num ( frame_data_block_num ),
        .frame_eof_bit        ( frame_eof_bit        ),
        .header_coded_bits    ( header_coded_bits    ),
        .data_coded_bits      ( data_coded_bits      )
    );

    // 如果当前symbol没发完(vio不可能出现), 则frame_ready无效
    link11_slew_tx_symbol_scheduler u_symbol_scheduler (
        .clk                  ( clk                  ),
        .rst_n                ( rst_n                ),
        .start                ( frame_ready          ),
        .data_block_num       ( frame_data_block_num ),
        .eof_bit              ( frame_eof_bit        ),
        .header_coded_bits    ( header_coded_bits    ),
        .data_coded_bits      ( data_coded_bits      ),
        .symbol_take          ( symbol_take          ),
        .symbol_valid         ( symbol_valid         ),
        .symbol_phase         ( symbol_phase         ),
        .busy                 ( scheduler_busy       ),
        .done                 ( done                 )
    );

    assign busy = builder_busy || scheduler_busy;

endmodule
