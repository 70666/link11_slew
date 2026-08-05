/*
    窗口内求和再求幅度平方, 不需要参与状态复位
    peak_finder需要demod_done或者rst_n复位, 没有复位问题
*/
module link11_slew_step2 #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16
)(
    input wire clk,
    input wire rst_n,
    input wire demod_done,      // 完成标志, 告知前导码寻找逻辑可以复位
    input wire envelope,
    input wire [LPF_WIDTH-1:0] signal_lpf_envelope_i, signal_lpf_envelope_q,
    input wire signal_lpf_envelope_strobe, 
    output wire [LPF_WIDTH-1:0] symbol_aligned_i, symbol_aligned_q,
    output wire symbol_aligned_strobe,
    output wire signal_valid_start,
    output wire symbol_aligned_envelope
);
    
localparam SEARCH_LENGTH = 3 * WINDOW_NUM;  // 即使第一个symbol不完整依然可以找到
localparam WRITE_DEPTH = SEARCH_LENGTH + SEARCH_LENGTH / 4;

localparam SUM_WIDTH = LPF_WIDTH + $clog2(WINDOW_NUM);
localparam SQUARE_SUM_WIDTH = 2*SUM_WIDTH;
localparam ADDRA_WIDTH = $clog2(WRITE_DEPTH);

localparam MOVING_SUM_LATENCY = $clog2(WINDOW_NUM) + 1;
localparam COMP_TO_MAG_LATENCY = 5;
localparam RAM_LATENCY = 2;
localparam PROBE_TO_INDEX_LATENCY = MOVING_SUM_LATENCY + COMP_TO_MAG_LATENCY;
localparam PROBE_TO_ADDRA_LATENCY = 1;

// MOVING_SUM_LATENCY clks, 算出一个窗口内的和
wire [SUM_WIDTH-1:0] sum_out_i, sum_out_q;
wire sum_out_strobe;
moving_sum #(
    .DATA_WIDTH ( LPF_WIDTH ),
    .WINDOW_NUM ( WINDOW_NUM ),
    .LATENCY    ( 1         ),
    .ARITH_IMPL_TYPE ( "LUT" ))
 u_moving_sum (
    .clk                     ( clk                          ),
    .rst_n                   ( rst_n                        ),
    .data_in_strobe          ( signal_lpf_envelope_strobe   ),
    .data_in_i               ( signal_lpf_envelope_i        ),
    .data_in_q               ( signal_lpf_envelope_q        ),

    .sum_out_i               ( sum_out_i                    ),
    .sum_out_q               ( sum_out_q                    ),
    .data_out_strobe         ( sum_out_strobe               )
);

// COMP_TO_MAG_LATENCY clks 平方和求窗口内和
wire [SQUARE_SUM_WIDTH-1:0] square_sum;
wire square_sum_strobe;
square_sum_strobe #(
    .DATA_WIDTH ( SUM_WIDTH ))
 u_square_sum_strobe (
    .clk          ( clk                 ),
    .in_strobe    ( sum_out_strobe      ),
    .i            ( sum_out_i           ),
    .q            ( sum_out_q           ),

    .square_sum   ( square_sum          ),
    .out_strobe   ( square_sum_strobe   )
);


// signal_lpf_envelope_strobe -> addra 1个延时
reg enb;
reg [$clog2(WRITE_DEPTH)-1:0] addrb;
wire [$clog2(WRITE_DEPTH)-1:0] addra;
wire [2*LPF_WIDTH:0] doutb; 
wire [2*LPF_WIDTH:0] ram_data_in = {envelope, signal_lpf_envelope_q, signal_lpf_envelope_i}; 
link11_slew_sync_ram_cache #(
    .WINDOW_NUM  ( WINDOW_NUM  ),
    .RAM_LATENCY ( RAM_LATENCY ),
    .DATA_WIDTH  ( 2*LPF_WIDTH + 1    ),
    .WRITE_DEPTH ( WRITE_DEPTH ))
 u_link11_slew_sync_ram_cache (
    .clk                     ( clk                          ),
    .rst_n                   ( rst_n                        ),
    .data_in_strobe          ( signal_lpf_envelope_strobe   ),
    .data_in                 ( ram_data_in                  ),
    .enb                     ( enb                          ),
    .addrb                   ( addrb                        ),

    .addra                   ( addra                        ),
    .doutb                   ( doutb                        )
);

// 对齐求自相关相对于输入地址带来的延时
wire [ADDRA_WIDTH-1:0] sum_mag_index;
link11_slew_step2_param_align #(
    .PROBE_TO_INDEX_LATENCY ( PROBE_TO_INDEX_LATENCY ),
    .PROBE_TO_ADDRA_LATENCY ( PROBE_TO_ADDRA_LATENCY ),
    .ADDRA_WIDTH            ( ADDRA_WIDTH            ))
 u_link11_slew_step2_param_align (
    .clk                         ( clk                         ),
    .addra                       ( addra                       ),
    .signal_lpf_envelope_strobe  ( signal_lpf_envelope_strobe  ),
    .envelope                    ( envelope                    ),

    .sum_mag_index               ( sum_mag_index               ),
    .sum_mag_probe               ( sum_mag_probe               ),
    .envelope_sum_mag            ( envelope_sum_mag            )
);

// 找到最大值, 并据此启动输出
link11_slew_step2_peak_finder #(
    .WINDOW_NUM    ( WINDOW_NUM    ),
    .ADDRA_WIDTH   ( ADDRA_WIDTH   ),
    .SUM_WIDTH     ( SQUARE_SUM_WIDTH     ),
    .RAM_LATENCY   ( RAM_LATENCY   ),
    .SEARCH_LENGTH ( SEARCH_LENGTH ),
    .WRITE_DEPTH   ( WRITE_DEPTH   ))
 u_link11_slew_step2_peak_finder (
    .clk                     ( clk                      ),
    .rst_n                   ( rst_n                    ),
    .envelope_sum_mag        ( envelope_sum_mag         ),
    .demod_done              ( demod_done               ),
    .sum_mag_probe           ( sum_mag_probe            ),
    .sum_mag                 ( square_sum               ),
    .sum_mag_index           ( sum_mag_index            ),

    .enb                     ( enb                      ),
    .addrb                   ( addrb                    ),
    .signal_valid_start      ( signal_valid_start       )
);

     
delay #(
    .DATA_WIDTH ( 1             ),
    .DELAY_CLK  ( RAM_LATENCY   ),
    .IMPL_TYPE  ( 0             ))
 u_delay_demod_data_strobe (
    .clk                     ( clk                  ),
    .data_in                 ( enb    ),

    .data_out                ( symbol_aligned_strobe   )
);

assign symbol_aligned_i = doutb[LPF_WIDTH-1:0];
assign symbol_aligned_q = doutb[2*LPF_WIDTH-1:LPF_WIDTH];
assign symbol_aligned_envelope = doutb[2*LPF_WIDTH];
endmodule