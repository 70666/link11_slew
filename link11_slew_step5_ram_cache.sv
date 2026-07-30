module link11_slew_step5_ram_cache #(
    parameter RAM_CACHE_DEPTH = 16,
    parameter SYMBOL_DATA_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire correcting,
    input wire [SYMBOL_DATA_WIDTH-1:0] symbol_i, symbol_q,
    input wire symbol_strobe,
    input wire preamble_aligned_start,
    output wire [SYMBOL_DATA_WIDTH-1:0] ram_cache_out_i, ram_cache_out_q,
    output wire ram_cache_out_strobe
);
    
localparam WRITE_WIDTH = 2*SYMBOL_DATA_WIDTH;
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
assign ram_cache_out_i = doutb[SYMBOL_DATA_WIDTH-1:0];
assign ram_cache_out_q = doutb[2*SYMBOL_DATA_WIDTH-1:SYMBOL_DATA_WIDTH];


always @(posedge clk ) begin
    if(~rst_n) begin
        dina <= 0;
        addra <= 0;
        wea <= 0;
    end else begin
        if(preamble_aligned_start) begin    // 开始写, 并且重置写地址, 确保从一个已知的状态读出
            addra <= 0;
            wea <= 0;
        end else begin      // 写状态
            wea <= symbol_strobe;
            dina <= {symbol_q, symbol_i};
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
        end else begin                      // 每次信号到来时, correcting变0会将状态复位至已知
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
    .clk                     ( clk      ),
    .wea                     ( wea      ),
    .enb                     ( enb      ),
    .dina                    ( dina     ),
    .addra                   ( addra    ),
    .addrb                   ( addrb    ),

    .doutb                   ( doutb    )
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