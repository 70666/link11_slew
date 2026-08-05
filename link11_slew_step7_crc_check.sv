`timescale 1ns / 1ps
// crc校验结果相对于viterbi_done有 4clks 延时
module link11_slew_step7_crc_check (
    input wire clk,
    input wire mode_data,           // 0:header 1:data
    input wire viterbi_done,        // decoded_bits有效标志       
    input wire [59:0] decoded_bits, // viterbi译码结果  
    output reg crc_check_pass,      // crc校验通过
    output reg crc_check_strobe     // crc校验通过有效标志  
);

reg data_strobe_headerblock;
reg [32:0] data_in_headerblock;
reg data_strobe_datablock;
reg [47:0] data_in_datablock;
reg [11:0] crc_in;                  // header 与data共用
wire crc_valid_headerblock;
wire crc_valid_datablock;
wire crc_out_strobe_headerblock;
wire crc_out_strobe_datablock;
wire [11:0] crc_out_headerblock;
wire [11:0] crc_out_datablock;

// 对viterbi译码结果按照mode_data分类
always @(posedge clk ) begin
    if(~mode_data)                  // header
    begin
        data_strobe_headerblock <= viterbi_done;
        data_in_headerblock <= decoded_bits[44:12];
        data_strobe_datablock <= 0;
        data_in_datablock <= 0;
    end
    else begin
        data_strobe_headerblock <= 0;
        data_in_headerblock <= 0;
        data_strobe_datablock <= viterbi_done;
        data_in_datablock <= decoded_bits[59:12];
    end
    crc_in <= decoded_bits[11:0];
    if(crc_out_strobe_headerblock) begin
        crc_check_pass <= crc_valid_headerblock;
        crc_check_strobe <= crc_out_strobe_headerblock;
    end else if(crc_out_strobe_datablock) begin
        crc_check_pass <= crc_valid_datablock;
        crc_check_strobe <= crc_out_strobe_datablock;
    end else begin
        crc_check_strobe <= 0;
    end
end

// crc校验模块, 2clks延时
crc_check #(
    .DATA_WIDTH ( 33         ),
    .CRC_WIDTH  ( 12         ),
    .CRC_POLY   ( 13'h1539   ))
 u_crc_check_header (
    .clk                     ( clk                          ),
    .data_strobe             ( data_strobe_headerblock      ),
    .data_in                 ( data_in_headerblock          ),
    .crc_in                  ( crc_in                       ),

    .crc_out_strobe          ( crc_out_strobe_headerblock   ),
    .crc_valid               ( crc_valid_headerblock        ),
    .crc_out                 ( crc_out_headerblock          )
);
crc_check #(
    .DATA_WIDTH ( 48         ),
    .CRC_WIDTH  ( 12         ),
    .CRC_POLY   ( 13'h1539   ))
 u_crc_check_data (
    .clk                     ( clk                          ),
    .data_strobe             ( data_strobe_datablock        ),
    .data_in                 ( data_in_datablock            ),
    .crc_in                  ( crc_in                       ),

    .crc_out_strobe          ( crc_out_strobe_datablock     ),
    .crc_valid               ( crc_valid_datablock          ),
    .crc_out                 ( crc_out_datablock            )
);

endmodule