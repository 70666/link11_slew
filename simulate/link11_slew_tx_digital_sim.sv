`timescale 1ns / 1ps

// Link-11 SLEW transmit symbol scheduler for simulation.
// Each 45-symbol coded field is followed by a 19-symbol reinsertion probe.
module link11_slew_tx_digital_sim #(
    parameter integer DATA_BLOCK_NUM = 1,
    parameter [32:0] HEADER_RAW_PAYLOAD = 33'b0,
    parameter [DATA_BLOCK_NUM*48-1:0] DATA_RAW_PAYLOAD = {DATA_BLOCK_NUM*48{1'b0}},
    parameter EOF_ALL_ONES = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire symbol_take,

    output wire [2:0] symbol_phase,
    output wire [1:0] tx_raw_dibit,
    output wire [2:0] tx_raw_phase,
    output wire       tx_raw_dibit_strobe,
    output wire [7:0] tx_scramble_idx,
    output wire [2:0] tx_scramble_sym,
    output wire [2:0] tx_symbol_phase,
    output wire       busy,
    output reg        done
);

    `include "link11_slew_preamble_iq_wire.vh"
    `LINK11_SLEW_PREAMBLE_IQ_WIRE_DECLARE

    localparam integer CODED_SYMBOL_NUM = 45;
    localparam integer REINSERTION_PROBE_SYMBOL_NUM = 19;
    localparam integer FIELD_INTERVAL_SYMBOL_NUM = CODED_SYMBOL_NUM + REINSERTION_PROBE_SYMBOL_NUM;
    localparam integer DATA_BLOCK_INDEX_WIDTH = (DATA_BLOCK_NUM <= 1) ? 1 : $clog2(DATA_BLOCK_NUM);
    localparam integer SCR_LINEAR_INDEX_WIDTH = $clog2((DATA_BLOCK_NUM + 2) * FIELD_INTERVAL_SYMBOL_NUM);
    localparam integer SCRAMBLE_SYMBOL_NUM = 160;

    localparam [3:0] ST_IDLE          = 4'd0;
    localparam [3:0] ST_PREAMBLE      = 4'd1;
    localparam [3:0] ST_HEADER        = 4'd2;
    localparam [3:0] ST_HEADER_PROBE  = 4'd3;
    localparam [3:0] ST_DATA          = 4'd4;
    localparam [3:0] ST_DATA_PROBE    = 4'd5;
    localparam [3:0] ST_EOF           = 4'd6;
    localparam [3:0] ST_EOF_PROBE     = 4'd7;

    reg [3:0] state;
    reg [$clog2(LINK11_SLEW_PREAMBLE_SYMBOL_NUM)-1:0] preamble_index;
    reg [5:0] field_symbol_index;
    reg [DATA_BLOCK_INDEX_WIDTH-1:0] data_block_index;
    wire [89:0] header_coded_bits;
    wire [89:0] data_coded_bits [0:DATA_BLOCK_NUM-1];
    wire [1:0] raw_dibit;
    wire [2:0] raw_qpsk_phase;
    wire [2:0] scr_sym;
    wire [7:0] scr_idx;
    wire [SCR_LINEAR_INDEX_WIDTH-1:0] scr_linear_idx;

    function automatic [2:0] iq_to_phase;
        input signed [15:0] i_data;
        input signed [15:0] q_data;
        begin
            if ((i_data > 0) && (q_data == 0)) iq_to_phase = 3'd0;
            else if ((i_data > 0) && (q_data > 0)) iq_to_phase = 3'd1;
            else if ((i_data == 0) && (q_data > 0)) iq_to_phase = 3'd2;
            else if ((i_data < 0) && (q_data > 0)) iq_to_phase = 3'd3;
            else if ((i_data < 0) && (q_data == 0)) iq_to_phase = 3'd4;
            else if ((i_data < 0) && (q_data < 0)) iq_to_phase = 3'd5;
            else if ((i_data == 0) && (q_data < 0)) iq_to_phase = 3'd6;
            else iq_to_phase = 3'd7;
        end
    endfunction

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

    // Combinational simulation encoder, no clock latency.
    link11_slew_tx_block_encoder_sim #(
        .DATA_WIDTH  ( 33                 ),
        .DATA_MODE   ( 1'b0               ),
        .RAW_PAYLOAD ( HEADER_RAW_PAYLOAD ))
    u_header_encoder (
        .coded_bits ( header_coded_bits )
    );

    genvar data_block_gen;
    generate
        for (data_block_gen = 0; data_block_gen < DATA_BLOCK_NUM; data_block_gen = data_block_gen + 1) begin : g_data_encoder
            // Combinational simulation encoder, no clock latency.
            link11_slew_tx_block_encoder_sim #(
                .DATA_WIDTH  ( 48 ),
                .DATA_MODE   ( 1'b1 ),
                .RAW_PAYLOAD ( DATA_RAW_PAYLOAD[(DATA_BLOCK_NUM - data_block_gen) * 48 - 1 -: 48] ))
            u_data_encoder (
                .coded_bits ( data_coded_bits[data_block_gen] )
            );
        end
    endgenerate

    scrambler_lut u_scrambler_lut (
        .scr_idx ( scr_idx ),
        .scr_sym ( scr_sym )
    );

    assign busy = (state != ST_IDLE);
    // Inverse of step7 deinterleave: each QPSK dibit carries bit k and bit 45+k.
    assign raw_dibit = (state == ST_HEADER) ? {header_coded_bits[field_symbol_index], header_coded_bits[CODED_SYMBOL_NUM + field_symbol_index]} :
                       (state == ST_DATA)   ? {data_coded_bits[data_block_index][field_symbol_index], data_coded_bits[data_block_index][CODED_SYMBOL_NUM + field_symbol_index]} :
                       (state == ST_EOF)    ? {2{EOF_ALL_ONES}} :
                                              2'b00;
    assign raw_qpsk_phase = dibit_to_qpsk_phase(raw_dibit);
    assign scr_linear_idx = (state == ST_HEADER) ? field_symbol_index :
                            (state == ST_HEADER_PROBE) ? CODED_SYMBOL_NUM + field_symbol_index :
                            (state == ST_DATA) ? (data_block_index + 1) * FIELD_INTERVAL_SYMBOL_NUM + field_symbol_index :
                            (state == ST_DATA_PROBE) ? (data_block_index + 1) * FIELD_INTERVAL_SYMBOL_NUM + CODED_SYMBOL_NUM + field_symbol_index :
                            (state == ST_EOF) ? (DATA_BLOCK_NUM + 1) * FIELD_INTERVAL_SYMBOL_NUM + field_symbol_index :
                                               (DATA_BLOCK_NUM + 1) * FIELD_INTERVAL_SYMBOL_NUM + CODED_SYMBOL_NUM + field_symbol_index;
    assign scr_idx = scr_linear_idx % SCRAMBLE_SYMBOL_NUM;
    assign symbol_phase = (state == ST_PREAMBLE) ? iq_to_phase($signed(LINK11_SLEW_PREAMBLE_I[preamble_index]), $signed(LINK11_SLEW_PREAMBLE_Q[preamble_index])) : raw_qpsk_phase + scr_sym;
    assign tx_raw_dibit = raw_dibit;
    assign tx_raw_phase = raw_qpsk_phase;
    assign tx_raw_dibit_strobe = (state == ST_HEADER) || (state == ST_DATA) || (state == ST_EOF);
    assign tx_scramble_idx = scr_idx;
    assign tx_scramble_sym = scr_sym;
    assign tx_symbol_phase = raw_qpsk_phase + scr_sym;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            preamble_index <= 0;
            field_symbol_index <= 0;
            data_block_index <= 0;
            done <= 1'b0;
        end else if (start) begin
            state <= ST_PREAMBLE;
            preamble_index <= 0;
            field_symbol_index <= 0;
            data_block_index <= 0;
            done <= 1'b0;
        end else if (symbol_take && (state == ST_PREAMBLE)) begin
            if (preamble_index == LINK11_SLEW_PREAMBLE_SYMBOL_NUM - 1) begin
                state <= ST_HEADER;
                field_symbol_index <= 0;
            end else begin
                preamble_index <= preamble_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_HEADER)) begin
            if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                state <= ST_HEADER_PROBE;
                field_symbol_index <= 0;
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_HEADER_PROBE)) begin
            if (field_symbol_index == REINSERTION_PROBE_SYMBOL_NUM - 1) begin
                state <= ST_DATA;
                field_symbol_index <= 0;
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_DATA)) begin
            if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                state <= ST_DATA_PROBE;
                field_symbol_index <= 0;
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_DATA_PROBE)) begin
            if (field_symbol_index == REINSERTION_PROBE_SYMBOL_NUM - 1) begin
                field_symbol_index <= 0;
                if (data_block_index == DATA_BLOCK_NUM - 1) begin
                    state <= ST_EOF;
                end else begin
                    data_block_index <= data_block_index + 1'b1;
                    state <= ST_DATA;
                end
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_EOF)) begin
            if (field_symbol_index == CODED_SYMBOL_NUM - 1) begin
                state <= ST_EOF_PROBE;
                field_symbol_index <= 0;
                done <= 1'b0;
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
                done <= 1'b0;
            end
        end else if (symbol_take && (state == ST_EOF_PROBE)) begin
            if (field_symbol_index == REINSERTION_PROBE_SYMBOL_NUM - 1) begin
                state <= ST_IDLE;
                field_symbol_index <= 0;
                done <= 1'b1;
            end else begin
                field_symbol_index <= field_symbol_index + 1'b1;
                done <= 1'b0;
            end
        end else begin
            done <= 1'b0;
        end
    end

endmodule
