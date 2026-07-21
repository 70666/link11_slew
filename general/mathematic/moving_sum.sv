// 延时: $clog2(WINDOW_NUM) * LATENCY
module moving_sum#(
    parameter DATA_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter LATENCY = 1,
    parameter ARITH_IMPL_TYPE = "LUT"
)(
    input wire clk,
    input wire rst_n,
    input wire data_in_strobe,
    input wire [DATA_WIDTH-1:0] data_in_i,
    input wire [DATA_WIDTH-1:0] data_in_q,
    output wire [DATA_WIDTH+$clog2(WINDOW_NUM)-1:0] sum_out_i,
    output wire [DATA_WIDTH+$clog2(WINDOW_NUM)-1:0] sum_out_q,
    output wire data_out_strobe
);


// 2.将包含绝对相位的信号进行累加
reg [DATA_WIDTH-1:0] adder_in_i_reg [WINDOW_NUM-1:0];
reg [DATA_WIDTH-1:0] adder_in_q_reg [WINDOW_NUM-1:0];
integer i;
always @(posedge clk ) begin
    if(~rst_n) begin
        for(i=0;i<WINDOW_NUM;i=i+1)begin
            adder_in_i_reg[i] <= 0;
            adder_in_q_reg[i] <= 0;
        end
    end else begin
        if(data_in_strobe) begin
            adder_in_i_reg[0] <= data_in_i;
            adder_in_q_reg[0] <= data_in_q;
            for(i=1;i<WINDOW_NUM;i=i+1)begin
                adder_in_i_reg[i] <= adder_in_i_reg[i-1];
                adder_in_q_reg[i] <= adder_in_q_reg[i-1];
            end
        end    
    end
end


AdderTree #(
    .IMPL_TYPE  ( ARITH_IMPL_TYPE  ),
    .DATA_WIDTH ( DATA_WIDTH ),
    .DATA_TYPE  ( 1  ),
    .OUT_WIDTH  ( DATA_WIDTH+$clog2(WINDOW_NUM)  ),
    .LATENCY    ( LATENCY    ),
    .DATA_NUM   ( WINDOW_NUM   ))
 u_AdderTree_metric_i (
    .clk       ( clk        ),
    .in_data   ( adder_in_i_reg    ),

    .sum_out   ( sum_out_i    )
);AdderTree #(
    .IMPL_TYPE  ( ARITH_IMPL_TYPE  ),
    .DATA_WIDTH ( DATA_WIDTH ),
    .DATA_TYPE  ( 1  ),
    .OUT_WIDTH  ( DATA_WIDTH+$clog2(WINDOW_NUM)  ),
    .LATENCY    ( LATENCY    ),
    .DATA_NUM   ( WINDOW_NUM   ))
 u_AdderTree_metric_q (
    .clk       ( clk        ),
    .in_data   ( adder_in_q_reg    ),

    .sum_out   ( sum_out_q    )
);

// 对齐strobe
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( $clog2(WINDOW_NUM) * LATENCY + 1 ),
    .IMPL_TYPE  ( 0  ))
 u_delay_envelope (
    .clk                     ( clk                      ),
    .data_in                 ( data_in_strobe           ),

    .data_out                ( data_out_strobe          )
);
endmodule