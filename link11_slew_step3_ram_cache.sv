module link11_slew_step3_ram_cache #(
    parameter RAM_CACHE_DEPTH = 16,
    parameter LPF_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire correcting,
    input wire [LPF_WIDTH-1:0] symbol_aligned_i, symbol_aligned_q,
    input wire symbol_aligned_strobe,
    input wire signal_valid_start,
    output wire [LPF_WIDTH-1:0] ram_cache_out_i, ram_cache_out_q,
    output wire ram_cache_out_strobe
);
    
localparam WRITE_WIDTH = 2*LPF_WIDTH;
localparam WRITE_DEPTH = RAM_CACHE_DEPTH;
localparam READ_WIDTH = WRITE_WIDTH;
localparam RAM_LATENCY = 1;                 // 不准改这个数

localparam ADDR_WIDTH = $clog2(WRITE_DEPTH);


reg wea;
reg [WRITE_WIDTH-1:0] dina;
reg [ADDR_WIDTH-1:0] addra;

reg enb;
reg [ADDR_WIDTH-1:0] addrb;
wire [READ_WIDTH-1:0] doutb;
assign ram_cache_out_i = doutb[LPF_WIDTH-1:0];
assign ram_cache_out_q = doutb[2*LPF_WIDTH-1:LPF_WIDTH];

reg ram_writing;

always @(posedge clk ) begin
    if(~rst_n) begin
        dina <= 0;
        addra <= 0;
        wea <= 0;
        ram_writing <= 0;
    end else begin
        if(signal_valid_start) begin
            ram_writing <= 1;
            wea <= 0;
        end else if(demod_done) begin
            ram_writing <= 0;
            wea <= 0;
        end else if(ram_writing & symbol_aligned_strobe) begin
            wea <= 1;
            dina <= {symbol_aligned_q, symbol_aligned_i};
        end else begin
            wea <= 0;
        end
        if(wea) begin
            if(addra < WRITE_DEPTH - 1) begin
                addra <= addra + 1;
            end else begin
                addra <= 0;
            end
        end
    end
end

always @(posedge clk ) begin
    if(~rst_n) begin
        enb <= 0;
        addrb <= 0;
    end else begin
        enb <= correcting & symbol_aligned_strobe;
        if(enb) begin
            if(addrb < WRITE_DEPTH - 1 ) begin
                addrb <= addrb + 1;
            end else begin
                addrb <= 0;
            end
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