module link11_slew_step4_peak_search #(
    parameter LPF_WIDTH = 16,
    // 互相关已知序列的最后一个symbol对应索引
    parameter SYMBOL_NUMS_TO_FIND = 3,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 5,
    parameter PREAMBLE_SYMBOL_NUM = 192
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [2*LPF_WIDTH+$clog2(SYMBOL_NUMS_TO_FIND)-1:0] correlation_i,
    input wire [2*LPF_WIDTH+$clog2(SYMBOL_NUMS_TO_FIND)-1:0] correlation_q,
    input wire correlation_strobe,
    output reg [LPF_WIDTH-1:0] phase_reference_i,
    output reg [LPF_WIDTH-1:0] phase_reference_q,
    output reg [$clog2(PREAMBLE_SYMBOL_NUM+1)-1:0] preamble_start_symbol_offset,
    output reg phase_reference_valid
);

// 第一个 correlation_strobe 对应的索引 
localparam FIRST_WINDOW_END_SYMBOL = KNOWN_SEQUENCE_END_SYMBOL + 1 - SYMBOL_NUMS_TO_FIND;

localparam COR_WIDTH = 2*LPF_WIDTH+$clog2(SYMBOL_NUMS_TO_FIND);
localparam MAG_LATENCY = 3;
localparam SYMBOL_INDEX_WIDTH = $clog2(PREAMBLE_SYMBOL_NUM + 1);

wire [COR_WIDTH-1:0] correlation_mag;
wire correlation_mag_strobe;
wire [COR_WIDTH-1:0] correlation_i_aligned;
wire [COR_WIDTH-1:0] correlation_q_aligned;

// 幅度估计带来 MAG_LATENCY clks延时.
complex_to_mag #(
    .DATA_WIDTH ( COR_WIDTH ))
 u_correlation_mag (
    .clk          ( clk                    ),
    .enable       ( 1'b1                   ),
    .reset        ( ~rst_n                 ),
    .i            ( correlation_i          ),
    .q            ( correlation_q          ),
    .input_strobe ( correlation_strobe     ),

    .mag          ( correlation_mag        ),
    .mag_stb      ( correlation_mag_strobe )
);

// 相关向量补MAG_LATENCY clks, 与幅度输出对齐.
delay #(
    .DATA_WIDTH ( 2 * COR_WIDTH ),
    .DELAY_CLK  ( MAG_LATENCY   ),
    .IMPL_TYPE  ( 0             ))
 u_delay_correlation_vector (
    .clk        ( clk                                            ),
    .data_in    ( {correlation_q, correlation_i}                 ),

    .data_out   ( {correlation_q_aligned, correlation_i_aligned} )
);

// 第几个symbol累加得到的峰值最大
reg [SYMBOL_INDEX_WIDTH-1:0] window_end_symbol;
reg [SYMBOL_INDEX_WIDTH-1:0] best_window_end_symbol;
reg [COR_WIDTH-1:0] best_mag;
reg [COR_WIDTH-1:0] best_i;
reg [COR_WIDTH-1:0] best_q;
reg search_finished;

// 相关结果依次对应窗口1~3, 2~4, 3~5, 因此末尾symbol索引从3递增.
always @(posedge clk) begin
    if(!rst_n) begin
        window_end_symbol <= FIRST_WINDOW_END_SYMBOL;
        best_window_end_symbol <= 0;
        best_mag <= 0;
        best_i <= 0;
        best_q <= 0;
        search_finished <= 0;
    end else if(demod_done) begin
        window_end_symbol <= FIRST_WINDOW_END_SYMBOL;   // 当前最大值对应RAM里存的第3个symbol
        best_window_end_symbol <= 0;
        best_mag <= 0;
        best_i <= 0;
        best_q <= 0;
        search_finished <= 0;
    end else if(correlation_mag_strobe) begin
        if((window_end_symbol == FIRST_WINDOW_END_SYMBOL) ||
           (correlation_mag > best_mag)) begin
            best_window_end_symbol <= window_end_symbol;
            best_mag <= correlation_mag;
            best_i <= correlation_i_aligned;
            best_q <= correlation_q_aligned;
        end

        if(window_end_symbol == PREAMBLE_SYMBOL_NUM) begin
            search_finished <= 1;
        end else begin
            window_end_symbol <= window_end_symbol + 1'b1;
        end
    end else begin
        search_finished <= 0;
    end
end

reg [COR_WIDTH-1:0] phase_i;
reg [COR_WIDTH-1:0] phase_q;
reg normalizing;
wire phase_normalized;

// 任一路非零分量到达符号位边界时, 公共左移结束.
assign phase_normalized =
    ((phase_i != 0) && (phase_i[COR_WIDTH-1] != phase_i[COR_WIDTH-2])) ||
    ((phase_q != 0) && (phase_q[COR_WIDTH-1] != phase_q[COR_WIDTH-2])) ||
    ((phase_i == 0) && (phase_q == 0));

// 搜索结束后的下一拍, best_*已经包含最后一个相关结果.
always @(posedge clk) begin
    if(!rst_n) begin
        phase_i <= 0;
        phase_q <= 0;
        preamble_start_symbol_offset <= 0;
        normalizing <= 0;
    end else if(demod_done) begin
        phase_i <= 0;
        phase_q <= 0;
        preamble_start_symbol_offset <= 0;
        normalizing <= 0;
    end else if(search_finished) begin
        phase_i <= best_i;
        phase_q <= best_q;
        if(best_window_end_symbol > KNOWN_SEQUENCE_END_SYMBOL) begin
            preamble_start_symbol_offset <=
                best_window_end_symbol - KNOWN_SEQUENCE_END_SYMBOL;
        end else begin
            preamble_start_symbol_offset <= 0;
        end
        normalizing <= 1;
    end else if(normalizing) begin
        if(phase_normalized) begin
            normalizing <= 0;
        end else begin
            phase_i <= phase_i << 1;
            phase_q <= phase_q << 1;
        end
    end
end

// 归一化完成时输出相关向量高位, 保持I/Q比例.
always @(posedge clk) begin
    if(!rst_n) begin
        phase_reference_i <= 0;
        phase_reference_q <= 0;
        phase_reference_valid <= 0;
    end else if(demod_done) begin
        phase_reference_i <= 0;
        phase_reference_q <= 0;
        phase_reference_valid <= 0;
    end else if(normalizing && phase_normalized) begin
        phase_reference_i <= phase_i[COR_WIDTH-1-:LPF_WIDTH];
        phase_reference_q <= phase_q[COR_WIDTH-1-:LPF_WIDTH];
        phase_reference_valid <= 1;
    end else begin
        phase_reference_valid <= 0;
    end
end

endmodule
