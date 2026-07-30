module link11_slew_step3_phase_cor_est #(
    parameter SYMBOL_NUM_TO_EST = 16,       
    parameter WINDOW_NUM = 16,
    parameter LPF_WIDTH = 16,
    parameter CORDIC_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    input wire signal_valid_start,                                                  // start -> enb -> doutb/strobe 期间至少跨2个时钟
    input wire [LPF_WIDTH-1:0] symbol_aligned_i,
    input wire [LPF_WIDTH-1:0] symbol_aligned_q,
    input wire symbol_aligned_strobe,
    output reg signed [CORDIC_WIDTH-2:0] phase_cor_est_i,
    output reg signed [CORDIC_WIDTH-2:0] phase_cor_est_q,
    output reg phase_cor_est_strobe
);

localparam SAMPLE_NUM_IN_SYMBOL = WINDOW_NUM - 1;                                   // 相位作差只能是WINDOW_NUM - 1, 确保作差不会跨越symbol
// 模块延时
localparam MIXER_LATENCY = 7;
localparam SAMPLE_ADDER_LATENCY = 2;
localparam SYMBOL_ADDER_LATENCY = 2;
// 位宽计算
localparam MIXER_OUT_WIDTH = 2*LPF_WIDTH;
localparam SAMPLE_CNT_WIDTH = $clog2(WINDOW_NUM) + 1;
localparam SYMBOL_CNT_WIDTH = $clog2(SYMBOL_NUM_TO_EST) + 1;
localparam SAMPLE_SUM_WIDTH = MIXER_OUT_WIDTH + $clog2(SAMPLE_NUM_IN_SYMBOL);
localparam PHASE_COR_WIDTH = SAMPLE_SUM_WIDTH + $clog2(SYMBOL_NUM_TO_EST);



reg [SAMPLE_CNT_WIDTH-1:0] cnt_samples_in_symbol;
reg [SYMBOL_CNT_WIDTH-1:0] cnt_symbols_to_est;
reg [LPF_WIDTH-1:0] last_sample_i, last_sample_q;
reg [LPF_WIDTH-1:0] current_sample_i, current_sample_q;
reg mixer_in_strobe;

// 只在当前 symbol 内做相邻采样相位差, 跳过 sample0, 避免跨 symbol 相位差混入估计.
always @(posedge clk) begin
    if(~rst_n) begin
        cnt_samples_in_symbol <= 0;
        cnt_symbols_to_est <= 0;
        last_sample_i <= 0;
        last_sample_q <= 0;
        mixer_in_strobe <= 1'b0;
    end else if(signal_valid_start) begin
        cnt_samples_in_symbol <= 0;
        cnt_symbols_to_est <= 0;
        last_sample_i <= 0;
        last_sample_q <= 0;
        mixer_in_strobe <= 1'b0;
    end else if(symbol_aligned_strobe) begin
        current_sample_i <= symbol_aligned_i;
        current_sample_q <= symbol_aligned_q;
        last_sample_i <= current_sample_i;
        last_sample_q <= current_sample_q;
        mixer_in_strobe <= (cnt_samples_in_symbol != 0) &&                      // 第一个不计入, 因为last_sample还没准备好
                           (cnt_samples_in_symbol <= SAMPLE_NUM_IN_SYMBOL);     // 一个symbol内共1,2,...,SAMPLE_NUM_IN_SYMBOL参与计算
        if(cnt_samples_in_symbol == WINDOW_NUM - 1) begin
            cnt_samples_in_symbol <= 0;
            if(cnt_symbols_to_est == SYMBOL_NUM_TO_EST - 1) begin               // 对于究竟要采几个SYMBOL允许有一个误差, 这里可能控制的不完全准确

            end else begin
                cnt_symbols_to_est <= cnt_symbols_to_est + 1'b1;
            end
        end else begin
            cnt_samples_in_symbol <= cnt_samples_in_symbol + 1'b1;
        end
    end else begin
        mixer_in_strobe <= 1'b0;
    end
end

wire mixer_out_strobe;
wire signed [MIXER_OUT_WIDTH-1:0] phase_diff_i;
wire signed [MIXER_OUT_WIDTH-1:0] phase_diff_q;
// x[n] * conj(x[n-1]) 得到相邻采样点相位差向量. 
mixer_strobe #(
    .A_DATA_WIDTH ( LPF_WIDTH ),
    .B_DATA_WIDTH ( LPF_WIDTH ),
    .IMPL_TYPE    ( "LUT"    ),
    .MODE         ( 0        ))
 u_mixer_phase_diff (
    .clk                     ( clk                ),
    .rst_n                   ( rst_n              ),
    .in_strobe               ( mixer_in_strobe    ),
    .ai                      ( current_sample_i   ),
    .aq                      ( current_sample_q   ),
    .bi                      ( last_sample_i      ),
    .bq                      ( last_sample_q      ),

    .out_strobe              ( mixer_out_strobe   ),
    .oi                      ( phase_diff_i       ),
    .oq                      ( phase_diff_q       )
);

wire [SAMPLE_CNT_WIDTH-1:0] phase_diff_index;
wire [SAMPLE_CNT_WIDTH-1:0] sample_sum_index;
wire [SYMBOL_CNT_WIDTH-1:0] phase_diff_symbol_index;
wire [SYMBOL_CNT_WIDTH-1:0] sample_sum_symbol_index;

// 对齐混频输出对应的 sample index.
delay #(
    .DATA_WIDTH ( SAMPLE_CNT_WIDTH ),
    .DELAY_CLK  ( MIXER_LATENCY    ),
    .IMPL_TYPE  ( 0                ))
 u_delay_mixer_sample_index (
    .clk        ( clk                   ),
    .data_in    ( cnt_samples_in_symbol ),

    .data_out   ( phase_diff_index      )
);

// 对齐 symbol 内累加结果对应的 sample index.
delay #(
    .DATA_WIDTH ( SAMPLE_CNT_WIDTH     ),
    .DELAY_CLK  ( SAMPLE_ADDER_LATENCY ),
    .IMPL_TYPE  ( 0                    ))
 u_delay_sample_adder_index (
    .clk        ( clk              ),
    .data_in    ( phase_diff_index ),

    .data_out   ( sample_sum_index )
);

// 对齐混频输出对应的 symbol index.
delay #(
    .DATA_WIDTH ( SYMBOL_CNT_WIDTH ),
    .DELAY_CLK  ( MIXER_LATENCY    ),
    .IMPL_TYPE  ( 0                ))
 u_delay_mixer_symbol_index (
    .clk        ( clk                ),
    .data_in    ( cnt_symbols_to_est ),

    .data_out   ( phase_diff_symbol_index )
);

// 对齐 symbol 内累加结果对应的 symbol index.
delay #(
    .DATA_WIDTH ( SYMBOL_CNT_WIDTH     ),
    .DELAY_CLK  ( SAMPLE_ADDER_LATENCY ),
    .IMPL_TYPE  ( 0                    ))
 u_delay_sample_adder_symbol_index (
    .clk        ( clk                     ),
    .data_in    ( phase_diff_symbol_index ),

    .data_out   ( sample_sum_symbol_index )
);

reg sample_adder_in_strobe;
reg signed [MIXER_OUT_WIDTH-1:0] sample_adder_in_i;
reg signed [MIXER_OUT_WIDTH-1:0] sample_adder_in_q;
reg signed [SAMPLE_SUM_WIDTH-1:0] phase_sum_temp_i;
reg signed [SAMPLE_SUM_WIDTH-1:0] phase_sum_temp_q;
wire sample_adder_out_strobe;
wire signed [SAMPLE_SUM_WIDTH-1:0] sample_adder_out_i;
wire signed [SAMPLE_SUM_WIDTH-1:0] sample_adder_out_q;

always @(posedge clk) begin
    if(~rst_n) begin
        sample_adder_in_strobe <= 1'b0;
        sample_adder_in_i <= 0;
        sample_adder_in_q <= 0;
    end else if(mixer_out_strobe) begin
        sample_adder_in_strobe <= 1'b1;
        sample_adder_in_i <= phase_diff_i;
        sample_adder_in_q <= phase_diff_q;
    end else begin
        sample_adder_in_strobe <= 1'b0;
    end
end

always @(posedge clk) begin
    if(~rst_n) begin
        phase_sum_temp_i <= 0;
        phase_sum_temp_q <= 0;
    end else if(signal_valid_start) begin
        phase_sum_temp_i <= 0;
        phase_sum_temp_q <= 0;
    end else if(symbol_aligned_strobe && (cnt_samples_in_symbol == 0)) begin
        phase_sum_temp_i <= 0;
        phase_sum_temp_q <= 0;
    end else if(sample_adder_out_strobe) begin
        phase_sum_temp_i <= sample_adder_out_i;
        phase_sum_temp_q <= sample_adder_out_q;
    end
end

// SAMPLE_ADDER_LATENCY clks, 累加一个 symbol 内选中的 SAMPLE_NUM_IN_SYMBOL 个相位差.
Adder_strobe #(
    .IMPL_TYPE ( "LUT"            ),
    .A_WIDTH   ( SAMPLE_SUM_WIDTH ),
    .B_WIDTH   ( MIXER_OUT_WIDTH  ),
    .A_TYPE    ( 1                ),
    .B_TYPE    ( 1                ),
    .OUT_WIDTH ( SAMPLE_SUM_WIDTH ),
    .LATENCY   ( SAMPLE_ADDER_LATENCY ))
 u_sample_phase_sum_i (
    .clk                     ( clk                       ),
    .data_in_strobe          ( sample_adder_in_strobe    ),
    .A                       ( phase_sum_temp_i          ),
    .B                       ( sample_adder_in_i         ),

    .data_out_strobe         ( sample_adder_out_strobe   ),
    .SUM                     ( sample_adder_out_i        )
);

// SAMPLE_ADDER_LATENCY clks, 与 I 路同延时累加 Q 路相位差.
Adder_strobe #(
    .IMPL_TYPE ( "LUT"            ),
    .A_WIDTH   ( SAMPLE_SUM_WIDTH ),
    .B_WIDTH   ( MIXER_OUT_WIDTH  ),
    .A_TYPE    ( 1                ),
    .B_TYPE    ( 1                ),
    .OUT_WIDTH ( SAMPLE_SUM_WIDTH ),
    .LATENCY   ( SAMPLE_ADDER_LATENCY ))
 u_sample_phase_sum_q (
    .clk                     ( clk                    ),
    .data_in_strobe          ( sample_adder_in_strobe ),
    .A                       ( phase_sum_temp_q       ),
    .B                       ( sample_adder_in_q      ),

    .data_out_strobe         (                        ),
    .SUM                     ( sample_adder_out_q     )
);

reg symbol_adder_in_strobe;
reg signed [SAMPLE_SUM_WIDTH-1:0] symbol_adder_in_i;
reg signed [SAMPLE_SUM_WIDTH-1:0] symbol_adder_in_q;
reg signed [PHASE_COR_WIDTH-1:0] phase_cor_temp_i;
reg signed [PHASE_COR_WIDTH-1:0] phase_cor_temp_q;
wire symbol_adder_out_strobe;
wire signed [PHASE_COR_WIDTH-1:0] symbol_adder_out_i;
wire signed [PHASE_COR_WIDTH-1:0] symbol_adder_out_q;
wire symbol_sum_is_last;
wire symbol_out_is_last;

assign symbol_sum_is_last = (sample_sum_symbol_index == SYMBOL_NUM_TO_EST - 1);

// SYMBOL_ADDER_LATENCY clks, 对齐跨 symbol 累加结果是否为最后一个估计 symbol.
delay #(
    .DATA_WIDTH ( 1                   ),
    .DELAY_CLK  ( SYMBOL_ADDER_LATENCY ),
    .IMPL_TYPE  ( 0                   ))
 u_delay_symbol_last_flag (
    .clk        ( clk                                  ),
    .data_in    ( symbol_adder_in_strobe && symbol_sum_is_last ),

    .data_out   ( symbol_out_is_last                   )
);

always @(posedge clk) begin
    if(~rst_n) begin
        symbol_adder_in_strobe <= 1'b0;
        symbol_adder_in_i <= 0;
        symbol_adder_in_q <= 0;
    end else if(sample_adder_out_strobe && (sample_sum_index == SAMPLE_NUM_IN_SYMBOL)) begin
        symbol_adder_in_strobe <= 1'b1;
        symbol_adder_in_i <= sample_adder_out_i;
        symbol_adder_in_q <= sample_adder_out_q;
    end else begin
        symbol_adder_in_strobe <= 1'b0;
    end
end

always @(posedge clk) begin
    if(~rst_n) begin
        phase_cor_temp_i <= 0;
        phase_cor_temp_q <= 0;
    end else if(signal_valid_start) begin
        phase_cor_temp_i <= 0;
        phase_cor_temp_q <= 0;
    end else if(symbol_adder_out_strobe) begin
        phase_cor_temp_i <= symbol_adder_out_i;
        phase_cor_temp_q <= symbol_adder_out_q;
    end
end

// 为满足要求, CORDIC最高位为符号位
normalize #(
    .DATA_WIDTH_IN  ( PHASE_COR_WIDTH  ),
    .DATA_WIDTH_OUT ( CORDIC_WIDTH-1 ))
 u_normalize (
    .clk                     ( clk                                   ),
    .rst_n                   ( rst_n                                 ),
    .data_in_strobe          ( symbol_out_is_last                    ),
    .data_in_i               ( symbol_adder_out_i  ),
    .data_in_q               ( symbol_adder_out_q  ),

    .data_out_strobe         ( phase_cor_est_strobe                  ),
    .data_out_i              ( phase_cor_est_i                           ),
    .data_out_q              ( phase_cor_est_q                           )
);

// SYMBOL_ADDER_LATENCY clks, 跨 SYMBOL_NUM_TO_EST 个 symbol 累加频偏相位差向量.
Adder_strobe #(
    .IMPL_TYPE ( "LUT"           ),
    .A_WIDTH   ( PHASE_COR_WIDTH ),
    .B_WIDTH   ( SAMPLE_SUM_WIDTH ),
    .A_TYPE    ( 1               ),
    .B_TYPE    ( 1               ),
    .OUT_WIDTH ( PHASE_COR_WIDTH ),
    .LATENCY   ( SYMBOL_ADDER_LATENCY ))
 u_symbol_phase_sum_i (
    .clk                     ( clk                       ),
    .data_in_strobe          ( symbol_adder_in_strobe    ),
    .A                       ( phase_cor_temp_i          ),
    .B                       ( symbol_adder_in_i         ),

    .data_out_strobe         ( symbol_adder_out_strobe   ),
    .SUM                     ( symbol_adder_out_i        )
);

// SYMBOL_ADDER_LATENCY clks, 与 I 路同延时累加 Q 路频偏相位差向量.
Adder_strobe #(
    .IMPL_TYPE ( "LUT"            ),
    .A_WIDTH   ( PHASE_COR_WIDTH  ),
    .B_WIDTH   ( SAMPLE_SUM_WIDTH ),
    .A_TYPE    ( 1                ),
    .B_TYPE    ( 1                ),
    .OUT_WIDTH ( PHASE_COR_WIDTH  ),
    .LATENCY   ( SYMBOL_ADDER_LATENCY ))
 u_symbol_phase_sum_q (
    .clk                     ( clk                    ),
    .data_in_strobe          ( symbol_adder_in_strobe ),
    .A                       ( phase_cor_temp_q       ),
    .B                       ( symbol_adder_in_q      ),

    .data_out_strobe         (                        ),
    .SUM                     ( symbol_adder_out_q     )
);

endmodule
