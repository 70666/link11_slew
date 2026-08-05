`timescale 1ns / 1ps
`include "link11_slew_preamble_pkg.sv"
// 按前导码, header, data, EOM 的顺序输出已调制的 3-bit symbol 相位.
module link11_slew_tx_symbol_scheduler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  data_block_num,
    input  wire        eof_bit,
    input  wire [89:0] header_coded_bits,
    input  wire [89:0] data_coded_bits [0:14],
    input  wire        symbol_take,

    output wire       symbol_valid,
    output wire [2:0] symbol_phase,
    output wire       busy,
    output reg        done
);

    import link11_slew_preamble_pkg::*;

    localparam integer CODED_SYMBOL_NUM = 45;
    localparam integer PROBE_SYMBOL_NUM = 19;
    localparam integer SCRAMBLE_SYMBOL_NUM = 160;

    localparam [3:0] ST_IDLE          = 4'd0;
    localparam [3:0] ST_PREAMBLE      = 4'd1;
    localparam [3:0] ST_HEADER        = 4'd2;
    localparam [3:0] ST_HEADER_PROBE  = 4'd3;
    localparam [3:0] ST_DATA          = 4'd4;
    localparam [3:0] ST_DATA_PROBE    = 4'd5;
    localparam [3:0] ST_EOM           = 4'd6;
    localparam [3:0] ST_EOM_PROBE     = 4'd7;

    reg [3:0] state;
    reg [3:0] frame_data_block_num;
    reg       frame_eof_bit;
    reg [3:0] data_block_index;
    reg [7:0] preamble_index;
    reg [5:0] field_symbol_index;
    reg [7:0] scramble_index;

    wire [1:0] raw_dibit;
    wire [2:0] raw_qpsk_phase;
    wire [2:0] scramble_symbol;

    function automatic [2:0] dibit_to_qpsk_phase;
        input [1:0] dibit;
        begin
            case (dibit)
                2'b00: dibit_to_qpsk_phase = 3'd0;
                2'b01: dibit_to_qpsk_phase = 3'd2;
                2'b11: dibit_to_qpsk_phase = 3'd4;
                default: dibit_to_qpsk_phase = 3'd6;
            endcase
        end
    endfunction

    function automatic [7:0] next_scramble_index;
        input [7:0] current_index;
        begin
            if (current_index == SCRAMBLE_SYMBOL_NUM - 1) begin
                next_scramble_index = 8'd0;
            end else begin
                next_scramble_index = current_index + 1'b1;
            end
        end
    endfunction

    assign busy = (state != ST_IDLE);
    assign symbol_valid = (state != ST_IDLE);

    // 交织关系与接收端 deinterleave 互逆: 一个 dibit 取第 k 和第 45+k 位.
    assign raw_dibit = (state == ST_HEADER) ?
                       {header_coded_bits[field_symbol_index],
                        header_coded_bits[CODED_SYMBOL_NUM + field_symbol_index]} :
                       (state == ST_DATA) ?
                       {data_coded_bits[data_block_index][field_symbol_index],
                        data_coded_bits[data_block_index]
                                       [CODED_SYMBOL_NUM + field_symbol_index]} :
                       (state == ST_EOM) ? {2{frame_eof_bit}} :
                       2'b00;
    assign raw_qpsk_phase = dibit_to_qpsk_phase(raw_dibit);

    scrambler_lut u_scrambler_lut (
        .scr_idx ( scramble_index  ),
        .scr_sym ( scramble_symbol )
    );

    // 前导码不加扰, 后续字段和 probe 均连续加扰.
    assign symbol_phase = (state == ST_PREAMBLE) ?
                          PREAMBLE_SYM[preamble_index] :
                          raw_qpsk_phase + scramble_symbol;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            frame_data_block_num <= 4'b0;
            frame_eof_bit <= 1'b0;
            data_block_index <= 4'b0;
            preamble_index <= 8'b0;
            field_symbol_index <= 6'b0;
            scramble_index <= 8'b0;
            done <= 1'b0;
        end else begin
            case (state)
                // frame_builder 完成全部编码后, 从前导码第 0 个 symbol 启动.
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_PREAMBLE;
                        frame_data_block_num <= data_block_num;
                        frame_eof_bit <= eof_bit;
                        data_block_index <= 4'b0;
                        preamble_index <= 8'b0;
                        field_symbol_index <= 6'b0;
                        scramble_index <= 8'b0;
                        done <= 1'b0;
                    end else begin
                        done <= 1'b0;
                    end
                end

                // 前导码固定 192 symbol, 不推进扰码 index.
                ST_PREAMBLE: begin
                    if (symbol_take) begin
                        if (preamble_index == 8'd191) begin
                            state <= ST_HEADER;
                            preamble_index <= 8'b0;
                            field_symbol_index <= 6'b0;
                            scramble_index <= 8'b0;
                        end else begin
                            preamble_index <= preamble_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                // header 固定 45 symbol, 第一个 symbol 使用 scramble index 0.
                ST_HEADER: begin
                    if (symbol_take) begin
                        scramble_index <= next_scramble_index(scramble_index);
                        if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                            state <= ST_HEADER_PROBE;
                            field_symbol_index <= 6'b0;
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                // probe 固定 19 symbol, 原始 dibit 为 00, 扰码连续.
                ST_HEADER_PROBE: begin
                    if (symbol_take) begin
                        scramble_index <= next_scramble_index(scramble_index);
                        if (field_symbol_index == PROBE_SYMBOL_NUM - 1) begin
                            if (frame_data_block_num == 0) begin
                                state <= ST_EOM;
                            end else begin
                                state <= ST_DATA;
                            end
                            field_symbol_index <= 6'b0;
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                ST_DATA: begin
                    if (symbol_take) begin
                        scramble_index <= next_scramble_index(scramble_index);
                        if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                            state <= ST_DATA_PROBE;
                            field_symbol_index <= 6'b0;
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                // 每个 data block 后都插入 probe, 最后一块结束后进入 EOM.
                ST_DATA_PROBE: begin
                    if (symbol_take) begin
                        scramble_index <= next_scramble_index(scramble_index);
                        if (field_symbol_index == PROBE_SYMBOL_NUM - 1) begin
                            field_symbol_index <= 6'b0;
                            if (data_block_index == frame_data_block_num - 1'b1) begin
                                state <= ST_EOM;
                            end else begin
                                state <= ST_DATA;
                                data_block_index <= data_block_index + 1'b1;
                            end
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                // EOM 固定 45 symbol, 每个 dibit 由本帧锁存的 eof_bit 选择.
                ST_EOM: begin
                    if (symbol_take) begin
                        scramble_index <= next_scramble_index(scramble_index);
                        if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                            state <= ST_EOM_PROBE;
                            field_symbol_index <= 6'b0;
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                        end
                    end
                    done <= 1'b0;
                end

                // 最后一个 probe symbol 被波形域接收后, 产生一拍 done.
                ST_EOM_PROBE: begin
                    if (symbol_take) begin
                        if (field_symbol_index == PROBE_SYMBOL_NUM - 1) begin
                            state <= ST_IDLE;
                            field_symbol_index <= 6'b0;
                            scramble_index <= next_scramble_index(scramble_index);
                            done <= 1'b1;
                        end else begin
                            field_symbol_index <= field_symbol_index + 1'b1;
                            scramble_index <= next_scramble_index(scramble_index);
                            done <= 1'b0;
                        end
                    end else begin
                        done <= 1'b0;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule
