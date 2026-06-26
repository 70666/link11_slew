module link11_slew_step4_symbol_average #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [LPF_WIDTH-1:0] data_in_i,
    input wire [LPF_WIDTH-1:0] data_in_q,
    input wire data_in_strobe,
    output wire [LPF_WIDTH-1:0] symbol_average_i,
    output wire [LPF_WIDTH-1:0] symbol_average_q,
    output wire symbol_average_strobe
);

// 使用不超过WINDOW_NUM的最大2次幂采样点, 平均值可直接取累加结果高位.
localparam bit IS_POW2 = ((WINDOW_NUM) & (WINDOW_NUM-1)) == 0;
localparam AVERAGE_SAMPLE_NUM =
    IS_POW2 ? (WINDOW_NUM) : (1 << ($clog2(WINDOW_NUM)-1));
localparam AVERAGE_SHIFT = $clog2(AVERAGE_SAMPLE_NUM);
localparam SUM_WIDTH = LPF_WIDTH + AVERAGE_SHIFT;
localparam AVERAGE_LATENCY = AVERAGE_SHIFT + 1;
localparam SAMPLE_INDEX_WIDTH = (WINDOW_NUM <= 2) ? 1 : $clog2(WINDOW_NUM);

reg [SAMPLE_INDEX_WIDTH-1:0] sample_index;
wire average_input_marker;
wire [SUM_WIDTH-1:0] sum_i;
wire [SUM_WIDTH-1:0] sum_q;
wire sum_strobe_unused;

initial begin
    if(WINDOW_NUM < 3) begin
        $error("WINDOW_NUM must be at least 3");
    end
end

always @(posedge clk) begin
    if(!rst_n) begin
        sample_index <= 0;
    end else if(demod_done) begin
        sample_index <= 0;
    end else if(data_in_strobe) begin
        if(sample_index == WINDOW_NUM - 1) begin
            sample_index <= 0;
        end else begin
            sample_index <= sample_index + 1'b1;
        end
    end
end

// 标识一个窗口内加数已经遍历完毕
assign average_input_marker =
    data_in_strobe && (sample_index == AVERAGE_SAMPLE_NUM - 1);
assign symbol_average_i = sum_i[SUM_WIDTH-1-:LPF_WIDTH];
assign symbol_average_q = sum_q[SUM_WIDTH-1-:LPF_WIDTH];

// 该滑动和带来 AVERAGE_SHIFT clks数据延时.
moving_sum #(
    .DATA_WIDTH ( LPF_WIDTH         ),
    .WINDOW_NUM ( AVERAGE_SAMPLE_NUM),
    .LATENCY    ( 1                 ))
 u_symbol_sum (
    .clk                     ( clk                ),
    .rst_n                   ( rst_n              ),
    .data_in_strobe          ( data_in_strobe     ),
    .data_in_i               ( data_in_i          ),
    .data_in_q               ( data_in_q          ),

    .sum_out_i               ( sum_i              ),
    .sum_out_q               ( sum_q              ),
    .data_out_strobe         ( sum_strobe_unused  )
);

// 该延时将symbol结束标志对齐到平均值, 延时为AVERAGE_LATENCY clks.
delay #(
    .DATA_WIDTH ( 1               ),
    .DELAY_CLK  ( AVERAGE_LATENCY ),
    .IMPL_TYPE  ( 0               ))
 u_delay_symbol_average_strobe (
    .clk                     ( clk                    ),
    .data_in                 ( average_input_marker   ),

    .data_out                ( symbol_average_strobe  )
);

endmodule
