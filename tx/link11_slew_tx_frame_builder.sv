`timescale 1ns / 1ps

// 缓存 VIO 原始数据, 并在 start_tx 后依次生成 header 和 data 编码块.
module link11_slew_tx_frame_builder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_tx,
    input  wire        raw_data_valid,
    input  wire [3:0]  raw_data_index, // 0: header, 1..15: data block.
    input  wire [47:0] raw_data,
    input  wire [3:0]  data_block_num,
    input  wire        eof_bit,

    output wire        frame_ready,
    output wire        busy,
    output reg  [3:0]  frame_data_block_num,
    output reg         frame_eof_bit,
    output reg  [89:0] header_coded_bits,
    output reg  [89:0] data_coded_bits [0:14]
);

    localparam [2:0] ST_IDLE              = 3'd0;
    localparam [2:0] ST_HEADER_ENC_START  = 3'd1;
    localparam [2:0] ST_HEADER_ENC_WAIT   = 3'd2;
    localparam [2:0] ST_DATA_ENC_START    = 3'd3;
    localparam [2:0] ST_DATA_ENC_WAIT     = 3'd4;
    localparam [2:0] ST_FRAME_READY       = 3'd5;

    reg [2:0] state;
    reg       raw_data_valid_d;
    reg       start_tx_d;
    reg [32:0] header_raw_reg;
    reg [47:0] data_raw_reg [0:14];
    reg [3:0] prepare_block_index;

    wire       raw_data_valid_pos;
    wire       start_tx_pos;
    wire       encoder_start;
    wire       encoder_mode_data;
    wire [47:0] encoder_raw_data;
    wire       encoder_done;
    wire [89:0] encoder_coded_bits;

    integer raw_reset_index;
    integer coded_reset_index;

    assign raw_data_valid_pos = raw_data_valid && !raw_data_valid_d;
    assign start_tx_pos = start_tx && !start_tx_d;
    assign frame_ready = (state == ST_FRAME_READY);
    assign busy = (state != ST_IDLE);
    
    // 告诉block_encoder可以开始一次
    assign encoder_start = (state == ST_HEADER_ENC_START) ||
                           (state == ST_DATA_ENC_START);
    // 告诉block_encoder这次是什么数据类型
    assign encoder_mode_data = (state == ST_DATA_ENC_START);
    // 根据数据类型决定当前传递数据内容
    assign encoder_raw_data = (state == ST_HEADER_ENC_START) ?
                              {15'b0, header_raw_reg} :
                              data_raw_reg[prepare_block_index];

    // 编码器延时: header 为 80 clk, data 为 110 clk.
    link11_slew_tx_block_encoder u_block_encoder (
        .clk        ( clk                ),
        .rst_n      ( rst_n              ),
        .start      ( encoder_start      ),
        .mode_data  ( encoder_mode_data  ),
        .raw_data   ( encoder_raw_data   ),
        .busy       (                    ),
        .done       ( encoder_done       ),
        .coded_bits ( encoder_coded_bits )
    );

    // VIO 数据只允许在空闲状态更新, 避免发射过程中帧内容变化.
    always @(posedge clk) begin
        if (!rst_n) begin
            raw_data_valid_d <= 1'b0;
            start_tx_d <= 1'b0;
            header_raw_reg <= 33'b0;
            for (raw_reset_index = 0; raw_reset_index < 15;
                 raw_reset_index = raw_reset_index + 1) begin
                data_raw_reg[raw_reset_index] <= 48'b0;
            end
        end else begin
            raw_data_valid_d <= raw_data_valid;
            start_tx_d <= start_tx;
            if (raw_data_valid_pos && !busy) begin
                if (raw_data_index == 4'd0) begin
                    header_raw_reg <= raw_data[32:0];
                end else begin
                    data_raw_reg[raw_data_index-1'b1] <= raw_data;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            frame_data_block_num <= 4'b0;
            frame_eof_bit <= 1'b0;
            prepare_block_index <= 4'b0;
            header_coded_bits <= 90'b0;
            for (coded_reset_index = 0; coded_reset_index < 15;
                 coded_reset_index = coded_reset_index + 1) begin
                data_coded_bits[coded_reset_index] <= 90'b0;
            end
        end else begin
            case (state)
                // 检测 start_tx 上升沿并锁存本帧 data block 数量.
                ST_IDLE: begin
                    if (start_tx_pos) begin
                        state <= ST_HEADER_ENC_START;
                        frame_data_block_num <= data_block_num;
                        frame_eof_bit <= eof_bit;
                        prepare_block_index <= 4'b0;
                    end
                end

                // start 只保持一拍, 下一拍等待编码器完成.
                ST_HEADER_ENC_START: begin
                    state <= ST_HEADER_ENC_WAIT;
                end

                // header编码中, 等待 完成编码 CRC + TBCE
                ST_HEADER_ENC_WAIT: begin
                    if (encoder_done) begin
                        header_coded_bits <= encoder_coded_bits;
                        if (frame_data_block_num == 0) begin
                            state <= ST_FRAME_READY;
                        end else begin
                            state <= ST_DATA_ENC_START;
                        end
                    end
                end

                // 同HEADER对应部分
                ST_DATA_ENC_START: begin
                    state <= ST_DATA_ENC_WAIT;
                end

                // data block 按 index 依次编码, 最后一块完成后发布整帧.
                ST_DATA_ENC_WAIT: begin
                    if (encoder_done) begin
                        data_coded_bits[prepare_block_index] <= encoder_coded_bits;
                        if (prepare_block_index == frame_data_block_num - 1'b1) begin
                            state <= ST_FRAME_READY;
                            prepare_block_index <= 4'b0;
                        end else begin
                            state <= ST_DATA_ENC_START;
                            prepare_block_index <= prepare_block_index + 1'b1;
                        end
                    end
                end

                // frame_ready 保持一拍, 供 symbol 调度器锁存并启动.
                ST_FRAME_READY: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
