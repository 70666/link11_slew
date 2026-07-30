module link11_slew_step4_ram_cache #(
    parameter DATA_WIDTH = 1,
    parameter CACHE_DEPTH = 1,
    parameter CACHE_RAM_LATENCY = 1,
    parameter CACHE_ADDR_WIDTH = 1
) (
    input wire clk,
    input wire rst_n,
    input wire freq_corrected_start,
    input wire data_in_strobe,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire cache_read_enable,
    input wire [CACHE_ADDR_WIDTH-1:0] cache_read_addr,
    output wire [DATA_WIDTH-1:0] cache_read_data,
    output wire cache_read_data_strobe
);

reg [CACHE_ADDR_WIDTH-1:0] cache_write_addr;


// 粗频偏信号缓存入RAM逻辑
always @(posedge clk) begin
    if(!rst_n) begin
        cache_write_addr <= 0;
    end else if(freq_corrected_start) begin
        cache_write_addr <= 0;
    end else if(data_in_strobe) begin
        if(cache_write_addr == CACHE_DEPTH - 1) begin
            cache_write_addr <= 0;
        end else begin
            cache_write_addr <= cache_write_addr + 1'b1;
        end
    end
end


// 该RAM带来CACHE_RAM_LATENCY clks读延时.
sdpram_wrapper #(
    .WRITE_WIDTH ( DATA_WIDTH     ),
    .WRITE_DEPTH ( CACHE_DEPTH       ),
    .READ_WIDTH  ( DATA_WIDTH     ),
    .RAM_LATENCY ( CACHE_RAM_LATENCY ))
 u_data_cache (
    .clk                     ( clk                    ),
    .wea                     ( data_in_strobe         ),
    .enb                     ( cache_read_enable      ),
    .dina                    ( data_in              ),
    .addra                   ( cache_write_addr       ),
    .addrb                   ( cache_read_addr        ),

    .doutb                   ( cache_read_data        )
);
    

delay #(
    .DATA_WIDTH ( 1                         ),
    .DELAY_CLK  ( CACHE_RAM_LATENCY         ),
    .IMPL_TYPE  ( 0                         ))
 u_delay (
    .clk        ( clk                       ),
    .data_in    ( cache_read_enable         ),

    .data_out   ( cache_read_data_strobe    )
);
endmodule