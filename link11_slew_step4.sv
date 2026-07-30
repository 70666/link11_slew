module link11_slew_step4 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16,
// 这个参数指的是从1开始计数, 已知序列的最后一个数的索引, 3, 4, 5. 这个参数根据AGC损失情况设, 越大对AGC容忍程度越高
    parameter FIND_SERIES_START_INDEX = 5,
// 一共用几个前导码作互相关
    parameter SYMBOL_NUMS_TO_FIND = 3,
    parameter PREAMBLE_SYMBOL_NUM = 192
) (
    input wire clk,
    input wire rst_n,
    input wire freq_corrected_start,
    input wire [LPF_WIDTH-1:0] freq_corrected_i,
    input wire [LPF_WIDTH-1:0] freq_corrected_q,
    input wire freq_corrected_strobe,
    output wire preamble_aligned_start,
    output wire [2*LPF_WIDTH-1:0] preamble_aligned_data,
    output wire preamble_aligned_probe
);

localparam bit IS_POW2 = ((WINDOW_NUM) & (WINDOW_NUM-1)) == 0;
localparam AVERAGE_SAMPLE_NUM = IS_POW2 ? (WINDOW_NUM) : (1 << ($clog2(WINDOW_NUM)-1));
localparam AVERAGE_SHIFT = $clog2(AVERAGE_SAMPLE_NUM);
localparam CACHE_MARGIN = 64;
localparam CACHE_DEPTH = PREAMBLE_SYMBOL_NUM * WINDOW_NUM + CACHE_MARGIN;

localparam CACHE_ADDR_WIDTH = $clog2(CACHE_DEPTH);
localparam COR_WIDTH = 2 * LPF_WIDTH + $clog2(SYMBOL_NUMS_TO_FIND);
localparam SYMBOL_INDEX_WIDTH = $clog2(PREAMBLE_SYMBOL_NUM) + 1;

localparam PREAMBLE_CORRELATOR_LATENCY = 7 + $clog2(SYMBOL_NUMS_TO_FIND);
localparam SYMBOL_AVERAGE_LATENCY = AVERAGE_SHIFT + 1;
localparam CACHE_RAM_LATENCY = 2;





wire [COR_WIDTH-1:0] correlation_i;
wire [COR_WIDTH-1:0] correlation_q;
wire correlation_strobe;
// 对输入信号和已知序列做滑窗互相关
link11_slew_step4_window_correlator #(
    .LPF_WIDTH               ( LPF_WIDTH               ),
    .WINDOW_NUM              ( WINDOW_NUM              ),
    .SYMBOL_NUMS_TO_FIND     ( SYMBOL_NUMS_TO_FIND     ),
    .FIND_SERIES_START_INDEX ( FIND_SERIES_START_INDEX ),
    .PREAMBLE_SYMBOL_NUM     ( PREAMBLE_SYMBOL_NUM     ),
    .COR_WIDTH               ( COR_WIDTH               ))
 u_link11_slew_step4_window_correlator (
    .clk                     ( clk                                    ),
    .rst_n                   ( rst_n                                  ),
    .freq_corrected_start    ( freq_corrected_start                   ),
    .freq_corrected_i        ( freq_corrected_i       [LPF_WIDTH-1:0] ),
    .freq_corrected_q        ( freq_corrected_q       [LPF_WIDTH-1:0] ),
    .freq_corrected_strobe   ( freq_corrected_strobe                  ),

    .correlation_i           ( correlation_i          [COR_WIDTH-1:0] ),
    .correlation_q           ( correlation_q          [COR_WIDTH-1:0] ),
    .correlation_strobe      ( correlation_strobe                     )
);

wire peak_found;
assign preamble_aligned_start = peak_found;
wire [SYMBOL_INDEX_WIDTH-1:0] preamble_start_symbol_offset;
wire cache_read_enable;                         // ram读使能
wire [CACHE_ADDR_WIDTH-1:0] cache_read_addr;    // ram addrb
// 相关输入算出对应幅度, 找指定前导码数量内的自相关最大值, 找到后做归一化
link11_slew_step4_peak_search #(
    .LPF_WIDTH           ( LPF_WIDTH           ),
    .SYMBOL_NUMS_TO_FIND ( SYMBOL_NUMS_TO_FIND ),
    .PREAMBLE_SYMBOL_NUM ( PREAMBLE_SYMBOL_NUM ),
    .COR_WIDTH           ( COR_WIDTH           ),
    .CACHE_ADDR_WIDTH    ( CACHE_ADDR_WIDTH    ),
    .CACHE_DEPTH         ( CACHE_DEPTH         ),
    .WINDOW_NUM          ( WINDOW_NUM          ))
 u_link11_slew_step4_peak_search (
    .clk                     ( clk                                           ),
    .rst_n                   ( rst_n                                         ),
    .freq_corrected_start    ( freq_corrected_start                          ),
    .correlation_i           ( correlation_i          [COR_WIDTH-1:0]        ),
    .correlation_q           ( correlation_q          [COR_WIDTH-1:0]        ),
    .correlation_strobe      ( correlation_strobe                            ),
    .freq_corrected_strobe   ( freq_corrected_strobe                         ),

    .cache_read_enable       ( cache_read_enable                             ),
    .cache_read_addr         ( cache_read_addr        [CACHE_ADDR_WIDTH-1:0] ),
    .peak_found              ( peak_found                                    )
);

// 输出的已知边界粗频偏校准后信号
wire cache_read_data_strobe;                    // doutb 有效
wire [2*LPF_WIDTH-1:0] cache_read_data;         // ram doutb  
assign preamble_aligned_data = cache_read_data;
assign preamble_aligned_probe = cache_read_data_strobe;
// 对粗频偏校准信号进行缓存
link11_slew_step4_ram_cache #(
    .DATA_WIDTH        ( 2*LPF_WIDTH        ),
    .CACHE_DEPTH       ( CACHE_DEPTH       ),
    .CACHE_RAM_LATENCY ( CACHE_RAM_LATENCY ),
    .CACHE_ADDR_WIDTH  ( CACHE_ADDR_WIDTH  ))
 u_link11_slew_step4_ram_cache (
    .clk                     ( clk                                            ),
    .rst_n                   ( rst_n                                          ),
    .freq_corrected_start    ( freq_corrected_start                           ),
    .data_in_strobe          ( freq_corrected_strobe                          ),
    .data_in                 ( {freq_corrected_q, freq_corrected_i}           ),
    .cache_read_enable       ( cache_read_enable                              ),
    .cache_read_addr         ( cache_read_addr         [CACHE_ADDR_WIDTH-1:0] ),

    .cache_read_data         ( cache_read_data    [2*LPF_WIDTH-1:0]           ),
    .cache_read_data_strobe  ( cache_read_data_strobe                         )
);

endmodule
