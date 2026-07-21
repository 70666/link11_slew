`timescale 1ns / 1ps

// Encodes one Link-11 header or data block into its 90 transmitted bits.
// coded_bits[0] is the first convolution-coded bit before QPSK interleaving.
module link11_slew_tx_block_encoder_sim #(
    parameter integer DATA_WIDTH = 33,
    parameter         DATA_MODE = 1'b0,
    parameter [DATA_WIDTH-1:0] RAW_PAYLOAD = {DATA_WIDTH{1'b0}}
) (
    output reg [89:0] coded_bits
);

    reg [DATA_WIDTH+11:0] info_crc_bits;
    reg [5:0] encoder_state;
    reg [6:0] encoder_register;
    reg [1:0] convolution_bits;
    integer bit_index;
    integer coded_index;

    function automatic [11:0] calculate_crc12;
        input [DATA_WIDTH-1:0] data;
        reg [DATA_WIDTH+11:0] dividend;
        integer crc_bit_index;
        begin
            dividend = {data, 12'b0};
            for (crc_bit_index = DATA_WIDTH + 11; crc_bit_index >= 12;
                 crc_bit_index = crc_bit_index - 1) begin
                if (dividend[crc_bit_index]) begin
                    dividend[crc_bit_index -: 13] = dividend[crc_bit_index -: 13] ^ 13'h1539;
                end
            end
            calculate_crc12 = dividend[11:0];
        end
    endfunction

    // All inputs are parameters, so calculate this fixed simulation block once.
    initial begin
        // RAW_PAYLOAD MSB is the first information bit, matching crc_check.sv.
        info_crc_bits = {RAW_PAYLOAD, calculate_crc12(RAW_PAYLOAD)};
        coded_bits = 90'b0;

        // Tail-biting starts with the final six input bits as the encoder state.
        for (bit_index = 0; bit_index < 6; bit_index = bit_index + 1) begin
            encoder_state[5-bit_index] = info_crc_bits[bit_index];
        end

        for (bit_index = 0; bit_index < DATA_WIDTH + 12; bit_index = bit_index + 1) begin
            encoder_register = {info_crc_bits[DATA_WIDTH + 11 - bit_index], encoder_state};
            if (DATA_MODE) begin
                convolution_bits[1] = ^(encoder_register & 7'b1110011); // (163)_oct
                convolution_bits[0] = ^(encoder_register & 7'b1011101); // (135)_oct
            end else begin
                convolution_bits[1] = ^(encoder_register & 7'b1011011); // (133)_oct
                convolution_bits[0] = ^(encoder_register & 7'b1111001); // (171)_oct
            end

            if (DATA_MODE) begin
                coded_index = (bit_index >> 1) * 3;
                if (bit_index[0]) begin
                    coded_bits[coded_index + 2] = convolution_bits[1];
                end else begin
                    coded_bits[coded_index]     = convolution_bits[1];
                    coded_bits[coded_index + 1] = convolution_bits[0];
                end
            end else begin
                coded_bits[bit_index * 2]     = convolution_bits[1];
                coded_bits[bit_index * 2 + 1] = convolution_bits[0];
            end

            encoder_state = {info_crc_bits[DATA_WIDTH + 11 - bit_index], encoder_state[5:1]};
        end
    end

endmodule
