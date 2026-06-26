`timescale 1ns / 1ps

// Link-11 SLEW transmit symbol scheduler for simulation.
// It sends preamble first, then header, data blocks, and EOM.
module link11_slew_tx_digital_sim #(
    parameter integer HEADER_SYMBOL_NUM = 30,
    parameter integer DATA_SYMBOL_NUM = 30,
    parameter integer EOM_SYMBOL_NUM = 30,
    parameter integer DATA_BLOCK_NUM = 1,
    parameter integer DATA_TOTAL_SYMBOL_NUM = DATA_SYMBOL_NUM * DATA_BLOCK_NUM,
    parameter [HEADER_SYMBOL_NUM*3-1:0] HEADER_PAYLOAD = {HEADER_SYMBOL_NUM{3'd0}},
    parameter [DATA_TOTAL_SYMBOL_NUM*3-1:0] DATA_PAYLOAD = {DATA_TOTAL_SYMBOL_NUM{3'd0}},
    parameter [EOM_SYMBOL_NUM*3-1:0] EOM_PAYLOAD = {EOM_SYMBOL_NUM{3'd4}}
) (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire symbol_take,

    output wire [2:0] symbol_phase,
    output wire       busy,
    output reg        done
);

    `include "link11_slew_preamble_iq_wire.vh"
    `LINK11_SLEW_PREAMBLE_IQ_WIRE_DECLARE

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_PREAMBLE = 3'd1;
    localparam [2:0] ST_HEADER   = 3'd2;
    localparam [2:0] ST_DATA     = 3'd3;
    localparam [2:0] ST_EOM      = 3'd4;

    localparam integer PREAMBLE_INDEX_WIDTH = $clog2(LINK11_SLEW_PREAMBLE_SYMBOL_NUM);
    localparam integer MAX_HEADER_DATA_SYMBOL_NUM = (HEADER_SYMBOL_NUM > DATA_TOTAL_SYMBOL_NUM) ? HEADER_SYMBOL_NUM : DATA_TOTAL_SYMBOL_NUM;
    localparam integer MAX_PAYLOAD_SYMBOL_NUM = (MAX_HEADER_DATA_SYMBOL_NUM > EOM_SYMBOL_NUM) ? MAX_HEADER_DATA_SYMBOL_NUM : EOM_SYMBOL_NUM;
    localparam integer PAYLOAD_SYMBOL_INDEX_WIDTH = (MAX_PAYLOAD_SYMBOL_NUM <= 1) ? 1 : $clog2(MAX_PAYLOAD_SYMBOL_NUM);

    reg [2:0] state;
    reg [PREAMBLE_INDEX_WIDTH-1:0] preamble_index;
    reg [PAYLOAD_SYMBOL_INDEX_WIDTH-1:0] payload_index;

    function automatic [2:0] iq_to_phase;
        input signed [15:0] i_data;
        input signed [15:0] q_data;
        begin
            if ((i_data > 0) && (q_data == 0)) begin
                iq_to_phase = 3'd0;
            end else if ((i_data > 0) && (q_data > 0)) begin
                iq_to_phase = 3'd1;
            end else if ((i_data == 0) && (q_data > 0)) begin
                iq_to_phase = 3'd2;
            end else if ((i_data < 0) && (q_data > 0)) begin
                iq_to_phase = 3'd3;
            end else if ((i_data < 0) && (q_data == 0)) begin
                iq_to_phase = 3'd4;
            end else if ((i_data < 0) && (q_data < 0)) begin
                iq_to_phase = 3'd5;
            end else if ((i_data == 0) && (q_data < 0)) begin
                iq_to_phase = 3'd6;
            end else begin
                iq_to_phase = 3'd7;
            end
        end
    endfunction

    assign busy = (state != ST_IDLE);
    // Payload symbol 0 is stored in the highest 3 bits of each payload parameter.
    assign symbol_phase = (state == ST_PREAMBLE) ?
                          iq_to_phase($signed(LINK11_SLEW_PREAMBLE_I[preamble_index]),
                                      $signed(LINK11_SLEW_PREAMBLE_Q[preamble_index])) :
                          (state == ST_HEADER) ? HEADER_PAYLOAD[(HEADER_SYMBOL_NUM - payload_index) * 3 - 1 -: 3] :
                          (state == ST_DATA)   ? DATA_PAYLOAD[(DATA_TOTAL_SYMBOL_NUM - payload_index) * 3 - 1 -: 3] :
                                                 EOM_PAYLOAD[(EOM_SYMBOL_NUM - payload_index) * 3 - 1 -: 3];

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            preamble_index <= {PREAMBLE_INDEX_WIDTH{1'b0}};
            payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
            done <= 1'b0;
        end else if (start) begin
            state <= ST_PREAMBLE;
            preamble_index <= {PREAMBLE_INDEX_WIDTH{1'b0}};
            payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
            done <= 1'b0;
        end else if (symbol_take && (state == ST_PREAMBLE)) begin
            if (preamble_index == LINK11_SLEW_PREAMBLE_SYMBOL_NUM - 1) begin
                state <= ST_HEADER;
                preamble_index <= {PREAMBLE_INDEX_WIDTH{1'b0}};
                payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
            end else begin
                preamble_index <= preamble_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_HEADER)) begin
            if (payload_index == HEADER_SYMBOL_NUM - 1) begin
                state <= ST_DATA;
                payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
            end else begin
                payload_index <= payload_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_DATA)) begin
            if (payload_index == DATA_TOTAL_SYMBOL_NUM - 1) begin
                state <= ST_EOM;
                payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
            end else begin
                payload_index <= payload_index + 1'b1;
            end
            done <= 1'b0;
        end else if (symbol_take && (state == ST_EOM)) begin
            if (payload_index == EOM_SYMBOL_NUM - 1) begin
                state <= ST_IDLE;
                payload_index <= {PAYLOAD_SYMBOL_INDEX_WIDTH{1'b0}};
                done <= 1'b1;
            end else begin
                payload_index <= payload_index + 1'b1;
                done <= 1'b0;
            end
        end else begin
            done <= 1'b0;
        end
    end

endmodule
