/*
    利用前导码自相关算频偏的时候, 会使用很多的symbol, 因此需要将其缓存, 等到频偏信号生成后再将其读出
*/
module ram_cache #(
    parameter RAM_CACHE_DEPTH = 16,
    parameter RAM_WRITE_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire symbol_start,
    input wire correcting,
    input wire [RAM_WRITE_WIDTH-1:0] symbol,
    input wire symbol_strobe,

    output wire [RAM_WRITE_WIDTH-1:0] ram_cache_out,
    output wire ram_cache_out_strobe
);
    
localparam WRITE_WIDTH = RAM_WRITE_WIDTH;
localparam WRITE_DEPTH = RAM_CACHE_DEPTH;
localparam READ_WIDTH = WRITE_WIDTH;
localparam RAM_LATENCY = 1;                 

localparam ADDR_WIDTH = $clog2(WRITE_DEPTH);


reg wea;
reg [WRITE_WIDTH-1:0] dina;
reg [ADDR_WIDTH-1:0] addra;

reg enb;
reg [ADDR_WIDTH-1:0] addrb;
wire [READ_WIDTH-1:0] doutb;
assign ram_cache_out = doutb;



always @(posedge clk ) begin
    if(~rst_n) begin
        dina <= 0;
        addra <= 0;
        wea <= 0;
    end else begin
        if(symbol_start) begin  // 开始写, 并且重置写地址, 确保从一个已知的状态读出
            addra <= 0;
            wea <= 0;
        end else begin          // 写状态
            wea <= symbol_strobe;
            dina <= symbol;
            if(wea) begin
                if(addra < WRITE_DEPTH - 1) begin
                    addra <= addra + 1;
                end else begin
                    addra <= 0;
                end
            end
        end
    end
end

always @(posedge clk ) begin
    if(~rst_n) begin
        enb <= 0;
        addrb <= 0;
    end else begin
        if(correcting) begin
            enb <= symbol_strobe;
            if(enb) begin
                if(addrb < WRITE_DEPTH - 1 ) begin
                    addrb <= addrb + 1;
                end else begin
                    addrb <= 0;
                end
            end
        end else begin              // 每次信号到来时, correcting变0会将状态复位至已知
            enb <= 0;
            addrb <= 0;
        end   
    end
end

sdpram_wrapper #(
    .WRITE_WIDTH ( WRITE_WIDTH ),
    .WRITE_DEPTH ( WRITE_DEPTH ),
    .READ_WIDTH  ( READ_WIDTH  ),
    .RAM_LATENCY ( RAM_LATENCY ))
 u_sdpram_wrapper (
    .clk         ( clk          ),
    .wea         ( wea          ),
    .enb         ( enb          ),
    .dina        ( dina         ),
    .addra       ( addra        ),
    .addrb       ( addrb        ),

    .doutb       ( doutb        )
);

delay #(
    .DATA_WIDTH ( 1             ),
    .DELAY_CLK  ( RAM_LATENCY   ),
    .IMPL_TYPE  ( 0             ))
 u_delay (
    .clk         ( clk                  ),
    .data_in     ( enb                  ),

    .data_out    ( ram_cache_out_strobe )
);

endmodule