module link11_slew_sync_ram_cache#(
    parameter WINDOW_NUM = 16,
    parameter RAM_LATENCY = 2,
    parameter DATA_WIDTH = 16,
    parameter WRITE_DEPTH = 111
)(
    input wire clk,
    input wire rst_n,
    input wire                  data_in_strobe,
    input wire [DATA_WIDTH-1:0] data_in,

    input wire enb,
    input wire [$clog2(WRITE_DEPTH)-1:0] addrb,
    output reg [$clog2(WRITE_DEPTH)-1:0] addra,
    output wire [DATA_WIDTH-1:0] doutb
);


localparam WRITE_WIDTH = DATA_WIDTH;
localparam READ_WIDTH  = WRITE_WIDTH;

reg wea;
reg [DATA_WIDTH-1:0] dina;

always @(posedge clk ) begin
    if(~rst_n) begin
        wea <= 0;
        dina <= 0;
        addra <= 0;
    end else begin
        if(data_in_strobe) begin
            wea <= 1;
            dina <= data_in;
            addra <= (addra >= WRITE_DEPTH - 1)? 0 : (addra + 1); 
        end else begin
            wea <= 0;
            dina <= 0;
            addra <= addra;
        end
    end
end

// 调试用, 将同步信号也做延时
sdpram_wrapper #(
    .WRITE_WIDTH ( WRITE_WIDTH ),
    .WRITE_DEPTH ( WRITE_DEPTH ),
    .READ_WIDTH  ( READ_WIDTH  ),
    .RAM_LATENCY ( RAM_LATENCY ))
 u_sdpram_wrapper (
    .clk                     ( clk     ),
    .wea                     ( wea     ),
    .enb                     ( enb     ),
    .dina                    ( dina    ),
    .addra                   ( addra   ),
    .addrb                   ( addrb   ),

    .doutb                   ( doutb   )
);

endmodule