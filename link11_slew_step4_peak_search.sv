module link11_slew_step4_peak_search #(
    parameter LPF_WIDTH = 16,
    // 自相关窗口
    parameter SYMBOL_NUMS_TO_FIND = 3,
    parameter PREAMBLE_SYMBOL_NUM = 192,
    parameter COR_WIDTH = 666,
    parameter CACHE_ADDR_WIDTH = 6,
    parameter CACHE_DEPTH = 192,
    parameter WINDOW_NUM = 16
) (
    input wire clk,
    input wire rst_n,
    input wire freq_corrected_start,
    input wire [COR_WIDTH-1:0] correlation_i,
    input wire [COR_WIDTH-1:0] correlation_q,
    input wire correlation_strobe,
    input wire freq_corrected_strobe,
    output reg cache_read_enable,                         // ram读使能
    output reg [CACHE_ADDR_WIDTH-1:0] cache_read_addr,    // ram addrb
    output wire peak_found
);


localparam SQUARE_SUM_LATENCY = 5;
localparam ADDRESS_LATENCY = 3;
localparam SYMBOL_INDEX_WIDTH = $clog2(PREAMBLE_SYMBOL_NUM + 1);
localparam WINDOW_WIDTH = $clog2(WINDOW_NUM + 1);
localparam SQUARE_SUM_WIDTH = 2* COR_WIDTH;

wire [SQUARE_SUM_WIDTH-1:0] correlation_mag;
wire correlation_mag_strobe;

// 幅度估计带来 SQUARE_SUM_LATENCY clks延时.
square_sum_strobe #(
    .DATA_WIDTH ( COR_WIDTH ))
 u_square_sum_strobe (
    .clk                     ( clk                      ),
    .in_strobe               ( correlation_strobe       ),
    .i                       ( correlation_i            ),
    .q                       ( correlation_q            ),

    .square_sum              ( correlation_mag          ),
    .out_strobe              ( correlation_mag_strobe   )
);

// 第几个symbol累加得到的峰值最大
reg [SYMBOL_INDEX_WIDTH-1:0] window_end_symbol;
reg [SYMBOL_INDEX_WIDTH-1:0] best_window_end_symbol;
reg [SQUARE_SUM_WIDTH-1:0] best_mag;
reg search_finished;

// 寻找互相关最佳索引
always @(posedge clk) begin
    if(!rst_n) begin
        window_end_symbol <= SYMBOL_NUMS_TO_FIND;
        best_window_end_symbol <= 0;
        best_mag <= 0;
        search_finished <= 0;
    end else if(freq_corrected_start) begin
        window_end_symbol <= SYMBOL_NUMS_TO_FIND;           // 自相关窗口长度, 对应自相关窗口最后一个值的下一个值
        best_window_end_symbol <= 0;
        best_mag <= 0;
        search_finished <= 0;
    end else if(correlation_mag_strobe) begin
        if((window_end_symbol == SYMBOL_NUMS_TO_FIND) ||
           (correlation_mag > best_mag)) begin
            best_window_end_symbol <= window_end_symbol;
            best_mag <= correlation_mag;
        end

        if(window_end_symbol == PREAMBLE_SYMBOL_NUM) begin
            search_finished <= 1;
        end else begin
            window_end_symbol <= window_end_symbol + 1'b1;
        end
    end
end


wire search_finished_pos;
edge_detect #(
    .NO_LATENCY ( 0 ))
 u_edge_detect (
    .clk                     ( clk                  ),
    .flag                    ( search_finished      ),

    .flag_pos                ( search_finished_pos  ),
    .flag_neg                (                      )
);


// 搜索结束后的下一拍, best_*已经包含最后一个相关结果.
reg peak_found_pre;
reg [$clog2(PREAMBLE_SYMBOL_NUM):0] preamble_start_symbol_offset;
always @(posedge clk) begin
    if(!rst_n) begin
        preamble_start_symbol_offset <= 0;
        peak_found_pre <= 0;
    end else if(freq_corrected_start) begin
        preamble_start_symbol_offset <= 0;
        peak_found_pre <= 0;
    end else if(search_finished_pos) begin
        preamble_start_symbol_offset <= best_window_end_symbol;
        peak_found_pre <= 1;
    end else begin
        peak_found_pre <= 0; 
    end
end

delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( ADDRESS_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_peak_found (
    .clk                     ( clk                        ),
    .data_in                 ( peak_found_pre ),

    .data_out                ( peak_found )
);


// symbol偏移转换为采样地址带来ADDRESS_LATENCY clks延时.
wire [CACHE_ADDR_WIDTH-1:0] preamble_start_addr;
multiplier #(
    .IMPL_TYPE ( "DSP"              ),
    .A_WIDTH   ( SYMBOL_INDEX_WIDTH ),
    .B_WIDTH   ( WINDOW_WIDTH       ),
    .A_TYPE    ( 0                  ),
    .B_TYPE    ( 0                  ),
    .LATENCY   ( ADDRESS_LATENCY    ),
    .OUT_WIDTH ( CACHE_ADDR_WIDTH   ))
 u_start_address (
    .clk                     ( clk                          ),
    .A                       ( preamble_start_symbol_offset ),
    .B                       ( WINDOW_NUM                   ),

    .P                       ( preamble_start_addr          )
);

// 读缓存RAM控制
reg ram_reading = 0;
always @(posedge clk ) begin
    if(~rst_n) begin
        cache_read_enable <= 0;
        cache_read_addr <= 0;
        ram_reading <= 0;
    end else if(freq_corrected_start) begin   // 结束复位
        cache_read_enable <= 0;
        cache_read_addr <= 0;
        ram_reading <= 0;
    end else if(peak_found) begin   // 初始化
        cache_read_enable <= 0;
        cache_read_addr <= preamble_start_addr;
        ram_reading <= 1;
    end else if(ram_reading) begin
        if(freq_corrected_strobe) begin
            cache_read_enable <= 1;
        end else begin
            cache_read_enable <= 0;
        end
        if(cache_read_enable) begin
            if(cache_read_addr == CACHE_DEPTH - 1) begin
                cache_read_addr <= 0;
            end else begin
                cache_read_addr <= cache_read_addr + 1'b1;
            end
        end
    end
end
endmodule
