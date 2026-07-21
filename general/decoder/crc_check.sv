// 两个时钟延时
module crc_check#(
    parameter DATA_WIDTH = 33,
    parameter CRC_WIDTH = 12,
    parameter [CRC_WIDTH:0] CRC_POLY = 13'h1539     
)(
    input wire clk,
    input wire data_strobe,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [CRC_WIDTH-1:0] crc_in,
    output reg crc_out_strobe,
    output wire crc_valid,
    output reg [CRC_WIDTH-1:0] crc_out
);

reg [DATA_WIDTH-1:0] data_in_r;
reg [CRC_WIDTH-1:0] crc_in_r;
reg [CRC_WIDTH-1:0] crc_in_r2;
reg data_strobe_r;

assign crc_valid = (crc_out == crc_in_r2 && crc_out_strobe);

always @(posedge clk ) begin
    if(data_strobe) begin
       data_in_r <= data_in;
       crc_in_r <= crc_in; 
    end
    crc_in_r2 <= crc_in_r;
    data_strobe_r <= data_strobe;
    crc_out_strobe <= data_strobe_r;
    crc_out <= calculate_crc12(data_in_r);
end


function automatic logic [11:0] calculate_crc12(
    input logic [DATA_WIDTH-1:0] data
);
    logic [DATA_WIDTH+11:0] dividend;
    integer bit_index;
        begin
            dividend = {data, 12'b0};
            for (
                bit_index = DATA_WIDTH + 11;
                bit_index >= 12;
                bit_index = bit_index - 1
            ) begin
                if (dividend[bit_index] == 1'b1) begin

                    dividend[bit_index -: 13] =
                        dividend[bit_index -: 13] ^ CRC_POLY;
                end
            end
            calculate_crc12 = dividend[11:0];
        end
endfunction

endmodule