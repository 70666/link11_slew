module link11_slew_step4_window_correlator #(
    parameter LPF_WIDTH = 1,
    parameter WINDOW_NUM = 1,
    parameter SYMBOL_NUMS_TO_FIND = 1,
    parameter FIND_SERIES_START_INDEX = 1,
    parameter PREAMBLE_SYMBOL_NUM = 1,
    parameter COR_WIDTH = 1
) (
    input wire clk,
    input wire rst_n,
    input wire freq_corrected_start,
    input wire [LPF_WIDTH-1:0] freq_corrected_i,
    input wire [LPF_WIDTH-1:0] freq_corrected_q,
    input wire freq_corrected_strobe,
    output wire [COR_WIDTH-1:0] correlation_i,
    output wire [COR_WIDTH-1:0] correlation_q,
    output wire correlation_strobe
);
    


wire [LPF_WIDTH-1:0] symbol_average_i;
wire [LPF_WIDTH-1:0] symbol_average_q;
wire symbol_average_strobe;

// 求一个symbol内的相位平均值, 每个symbol只会有一个strobe产生
// 加法窗口末采样点 -> 求和结果延时为 SYMBOL_AVERAGE_LATENCY clks
link11_slew_step4_symbol_average #(
    .LPF_WIDTH  ( LPF_WIDTH  ),
    .WINDOW_NUM ( WINDOW_NUM ))
 u_symbol_average (
    .clk                     ( clk                       ),
    .rst_n                   ( rst_n                     ),
    .freq_corrected_start    ( freq_corrected_start      ),
    .data_in_i               ( freq_corrected_i          ),
    .data_in_q               ( freq_corrected_q          ),
    .data_in_strobe          ( freq_corrected_strobe     ),

    .symbol_average_i        ( symbol_average_i          ),
    .symbol_average_q        ( symbol_average_q          ),
    .symbol_average_strobe   ( symbol_average_strobe     )
);



// 将粗频偏平均信号与标准序列滑窗互相关
// PREAMBLE_CORRELATOR_LATENCY clks
link11_slew_step4_preamble_correlator #(
    .LPF_WIDTH                 ( LPF_WIDTH                 ),
    .SYMBOL_NUMS_TO_FIND       ( SYMBOL_NUMS_TO_FIND       ),
    .FIND_SERIES_START_INDEX   ( FIND_SERIES_START_INDEX    ),
    .PREAMBLE_SYMBOL_NUM       ( PREAMBLE_SYMBOL_NUM       ))
 u_link11_slew_step4_preamble_correlator (
    .clk                     ( clk                    ),
    .rst_n                   ( rst_n                  ),
    .freq_corrected_start    ( freq_corrected_start   ),
    .symbol_average_i        ( symbol_average_i       ),
    .symbol_average_q        ( symbol_average_q       ),
    .symbol_average_strobe   ( symbol_average_strobe  ),

    .correlation_i           ( correlation_i          ),
    .correlation_q           ( correlation_q          ),
    .correlation_strobe      ( correlation_strobe     )
);

endmodule
