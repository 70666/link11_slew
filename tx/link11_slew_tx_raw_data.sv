module link11_slew_tx_raw_data(
    input wire clk,
    input wire rst_n,
//  上升沿发一次
    input wire start_tx,
    // vio
    input wire raw_data_valid,          // 每次上升沿时, 更新指定index中的数据
    input wire [3:0] raw_data_index,    // 0:header 1 ~ 15:data
    input wire [47:0] raw_data,         // 自定义数据
    input wire [3:0] data_block_num     // data_block的数量
);

edge_detect #(
    .NO_LATENCY ( 0 ))
 u_edge_detectraw_data_valid (
    .clk                     ( clk        ),
    .flag                    ( raw_data_valid       ),

    .flag_pos                ( raw_data_valid_pos   ),
    .flag_neg                (    )
);

edge_detect #(
    .NO_LATENCY ( 0 ))
 u_edge_detectstart_tx (
    .clk                     ( clk        ),
    .flag                    ( start_tx       ),

    .flag_pos                ( start_tx_pos   ),
    .flag_neg                (    )
);

// 两个时钟延时
wire [11:0] crc_out_header;
wire [11:0] crc_out_data;
crc_check #(
    .DATA_WIDTH ( 33         ),
    .CRC_WIDTH  ( 12         ),
    .CRC_POLY   ( 13'h1539   ))
 u_crc_check_header (
    .clk                     ( clk                     ),
    .data_strobe             ( raw_data_valid_pos      ),
    .data_in                 ( raw_data[32:0]          ),
    .crc_in                  ( 0                       ),

    .crc_out_strobe          ( crc_out_strobe_header   ),
    .crc_valid               (                         ),
    .crc_out                 ( crc_out_header          )
);
crc_check #(
    .DATA_WIDTH ( 48         ),
    .CRC_WIDTH  ( 12         ),
    .CRC_POLY   ( 13'h1539   ))
 u_crc_check_data (
    .clk                     ( clk                     ),
    .data_strobe             ( raw_data_valid_pos      ),
    .data_in                 ( raw_data[47:0]          ),
    .crc_in                  ( 0                       ),

    .crc_out_strobe          ( crc_out_strobe_data     ),
    .crc_valid               (           ),
    .crc_out                 ( crc_out_data            )
);

reg [44:0] header_reg;
reg [59:0] data_reg [14:0];
always @(posedge clk ) begin
    if(~rst_n) begin
        data_reg <= {0};
        header_reg <= 0;
    end else if(crc_out_strobe_data || crc_out_strobe_header) begin
        if(raw_data_index == 0) begin
            header_reg <= {raw_data[32:0], crc_out_header};
        end else begin
            data_reg[raw_data_index-1] <= {raw_data, crc_out_data};
        end
    end
end


reg [2:0] state;
localparam IDLE = 0;    localparam PREAMBLE = 1;    localparam HEADER = 2;  localparam DATA = 3;    localparam EOM = 4;
always @(posedge clk ) begin
    
end
endmodule