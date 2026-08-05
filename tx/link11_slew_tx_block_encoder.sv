`timescale 1ns / 1ps

// 单块顺序编码器.
// Header: 33-bit 原始数据 + CRC-12, 1/2 尾咬卷积编码.
// Data: 48-bit 原始数据 + CRC-12, 2/3 puncture 尾咬卷积编码.
module link11_slew_tx_block_encoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        mode_data,           // 1: data, 0: header
    input  wire [47:0] raw_data,

    output reg         busy,
    output reg         done,
    output reg  [89:0] coded_bits
);

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_CRC    = 2'd1;
    localparam [1:0] ST_INIT   = 2'd2;
    localparam [1:0] ST_ENCODE = 2'd3;

    reg [1:0] state;
    reg       mode_data_reg;
    reg [47:0] raw_data_reg;
    reg [59:0] block_bits;
    reg [11:0] crc_reg;
    reg [5:0] crc_index;
    reg [5:0] encode_index;
    reg [5:0] encoder_state;

    wire crc_input_bit;
    wire [11:0] crc_next;
    wire encode_input_bit;
    wire [1:0] convolution_out;

//  每个时钟只进行一次crc移位
    function automatic [11:0] crc12_next;
        input [11:0] crc;
        input        data_bit;
        reg          feedback;
        begin
            feedback = crc[11] ^ data_bit;
            crc12_next = {crc[10:0], 1'b0};
            if (feedback) begin
                crc12_next = crc12_next ^ 12'h539;
            end
        end
    endfunction

//  每个时钟输出一个卷积编码bit
    function automatic [1:0] convolution_output;
        input [5:0] previous_state;
        input       current_input;
        input       data_mode;
        reg [6:0] encoder_register;
        begin
            encoder_register = {current_input, previous_state};
            if (data_mode) begin
                convolution_output[1] = ^(encoder_register & 7'b1110011); // (163)_oct, T1.
                convolution_output[0] = ^(encoder_register & 7'b1011101); // (135)_oct, T2.
            end else begin
                convolution_output[1] = ^(encoder_register & 7'b1011011); // (133)_oct, T1.
                convolution_output[0] = ^(encoder_register & 7'b1111001); // (171)_oct, T2.
            end
        end
    endfunction

    assign crc_input_bit = mode_data_reg ?
                           raw_data_reg[47-crc_index] :
                           raw_data_reg[32-crc_index];
    assign crc_next = crc12_next(crc_reg, crc_input_bit);
    assign encode_input_bit = mode_data_reg ?
                              block_bits[59-encode_index] :
                              block_bits[44-encode_index];
    assign convolution_out = convolution_output(
        encoder_state,
        encode_input_bit,
        mode_data_reg
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            mode_data_reg <= 1'b0;
            raw_data_reg <= 48'b0;
            block_bits <= 60'b0;
            crc_reg <= 12'b0;
            crc_index <= 6'b0;
            encode_index <= 6'b0;
            encoder_state <= 6'b0;
            busy <= 1'b0;
            done <= 1'b0;
            coded_bits <= 90'b0;
        end else begin
            case (state)
                // 锁存当前块, CRC 从原始数据最高位开始计算.
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_CRC;
                        mode_data_reg <= mode_data;
                        raw_data_reg <= raw_data;
                        crc_reg <= 12'b0;
                        crc_index <= 6'b0;
                        busy <= 1'b1;
                        done <= 1'b0;
                    end else begin
                        busy <= 1'b0;
                        done <= 1'b0;
                    end
                end

                // 每拍处理一个原始 bit, 最后一拍将 CRC 附加在数据低位.
                ST_CRC: begin
                    if (crc_index == (mode_data_reg ? 6'd47 : 6'd32)) begin
                        state <= ST_INIT;
                        if (mode_data_reg) begin
                            block_bits <= {raw_data_reg, crc_next};
                        end else begin
                            block_bits <= {15'b0, raw_data_reg[32:0], crc_next};
                        end
                        crc_reg <= crc_next;
                        busy <= 1'b1;
                        done <= 1'b0;
                    end else begin
                        crc_reg <= crc_next;
                        crc_index <= crc_index + 1'b1;
                        busy <= 1'b1;
                        done <= 1'b0;
                    end
                end

                // 尾咬初始状态取编码块最后 6 bit.
                ST_INIT: begin
                    state <= ST_ENCODE;
                    encoder_state <= {
                        block_bits[0], block_bits[1], block_bits[2],
                        block_bits[3], block_bits[4], block_bits[5]
                    };
                    encode_index <= 6'b0;
                    coded_bits <= 90'b0;
                    busy <= 1'b1;
                    done <= 1'b0;
                end

                // Header 输出 T1/T2, data 按 T1,T2,T1 周期执行 puncture.
                ST_ENCODE: begin
                    if (mode_data_reg) begin
                        if (!encode_index[0]) begin
                            coded_bits[(encode_index >> 1) * 3] <= convolution_out[1];
                            coded_bits[(encode_index >> 1) * 3 + 1] <= convolution_out[0];
                        end else begin
                            coded_bits[(encode_index >> 1) * 3 + 2] <= convolution_out[1];
                        end
                    end else begin
                        coded_bits[encode_index * 2] <= convolution_out[1];
                        coded_bits[encode_index * 2 + 1] <= convolution_out[0];
                    end

                    encoder_state <= {encode_input_bit, encoder_state[5:1]};
                    if (encode_index == (mode_data_reg ? 6'd59 : 6'd44)) begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        encode_index <= encode_index + 1'b1;
                        busy <= 1'b1;
                        done <= 1'b0;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule
