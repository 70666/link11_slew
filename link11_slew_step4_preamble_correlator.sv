module link11_slew_step4_preamble_correlator #(
    parameter LPF_WIDTH = 16,
    parameter SYMBOL_NUMS_TO_FIND = 3,          // 自相关窗口
    // 互相关已知序列的最后一个symbol对应索引
    parameter FIND_SERIES_START_INDEX = 5,      // 0 1 2 3 4 |5 ... 4+SYMBOL_NUMS_TO_FIND| 6 ... 191 192
    parameter PREAMBLE_SYMBOL_NUM = 192         // 找前导码的symbol数
) (
    input wire clk,
    input wire rst_n,
    input wire freq_corrected_start,
    input wire [LPF_WIDTH-1:0] symbol_average_i,
    input wire [LPF_WIDTH-1:0] symbol_average_q,
    input wire symbol_average_strobe,
    output wire [2*LPF_WIDTH+$clog2(SYMBOL_NUMS_TO_FIND)-1:0] correlation_i,
    output wire [2*LPF_WIDTH+$clog2(SYMBOL_NUMS_TO_FIND)-1:0] correlation_q,
    output wire correlation_strobe
);

localparam MIXER_OUT_WIDTH = 2 * LPF_WIDTH;
localparam COR_WIDTH = MIXER_OUT_WIDTH + $clog2(SYMBOL_NUMS_TO_FIND);

localparam COR_MIXER_LATENCY = 7;
localparam COR_ADDER_LATENCY = $clog2(SYMBOL_NUMS_TO_FIND);
localparam COR_LATENCY = COR_MIXER_LATENCY + COR_ADDER_LATENCY;


// 通过前导码模板找到需要的前导码序列
`include "link11_slew_preamble_iq_wire.vh"
`LINK11_SLEW_PREAMBLE_IQ_WIRE_DECLARE
wire [LPF_WIDTH-1:0] preamble_known_i [SYMBOL_NUMS_TO_FIND-1:0];
wire [LPF_WIDTH-1:0] preamble_known_q [SYMBOL_NUMS_TO_FIND-1:0];
genvar index;
generate
    for(index=0;index<SYMBOL_NUMS_TO_FIND;index=index+1) begin
        assign preamble_known_i[index] = 
        LINK11_SLEW_PREAMBLE_I[index+FIND_SERIES_START_INDEX][15-:LPF_WIDTH];
        assign preamble_known_q[index] = 
        LINK11_SLEW_PREAMBLE_Q[index+FIND_SERIES_START_INDEX][15-:LPF_WIDTH];
    end
endgenerate



integer i;
reg [LPF_WIDTH-1:0] symbol_i_d [SYMBOL_NUMS_TO_FIND-1:0];
reg [LPF_WIDTH-1:0] symbol_q_d [SYMBOL_NUMS_TO_FIND-1:0];
wire [LPF_WIDTH-1:0] symbol_i [SYMBOL_NUMS_TO_FIND-1:0];
wire [LPF_WIDTH-1:0] symbol_q [SYMBOL_NUMS_TO_FIND-1:0];
generate
    for(index=0;index<SYMBOL_NUMS_TO_FIND;index=index+1) begin
        if(index == 0) begin
            assign symbol_i[index] = symbol_average_i;
            assign symbol_q[index] = symbol_average_q;
        end else begin
            assign symbol_i[index] = (candidate_strobe)?
                symbol_i_d[index-1] : symbol_i_d[index];
            assign symbol_q[index] = (candidate_strobe)?
                symbol_q_d[index-1] : symbol_q_d[index];
        end
    end
endgenerate


reg [$clog2(PREAMBLE_SYMBOL_NUM+1)-1:0] received_symbol_num;
wire candidate_strobe;

// 第3个symbol开始, 每个平均值产生一个连续三symbol相关结果.
assign candidate_strobe =
    symbol_average_strobe &&
    (received_symbol_num >= SYMBOL_NUMS_TO_FIND - 1);

always @(posedge clk) begin
    if(!rst_n) begin
        for(i=0;i<SYMBOL_NUMS_TO_FIND-2;i=i+1) begin
            symbol_i_d[i] <= 0;
            symbol_q_d[i] <= 0;
        end
        received_symbol_num <= 0;
    end else if(freq_corrected_start) begin
        for(i=0;i<SYMBOL_NUMS_TO_FIND-2;i=i+1) begin
            symbol_i_d[i] <= 0;
            symbol_q_d[i] <= 0;
        end
        received_symbol_num <= 0;
    end else if(symbol_average_strobe) begin    
        for(i=0;i<SYMBOL_NUMS_TO_FIND-2;i=i+1) begin
            symbol_i_d[i+1] <= symbol_i_d[i];
            symbol_q_d[i+1] <= symbol_q_d[i];
            if(i == 0) begin 
                symbol_i_d[0] <= symbol_average_i;
                symbol_q_d[0] <= symbol_average_q;
            end
        end
        if(received_symbol_num < PREAMBLE_SYMBOL_NUM) begin
            received_symbol_num <= received_symbol_num + 1'b1;
        end
    end
end

wire [MIXER_OUT_WIDTH-1:0] cor_symbol_i[SYMBOL_NUMS_TO_FIND-1:0];
wire [MIXER_OUT_WIDTH-1:0] cor_symbol_q[SYMBOL_NUMS_TO_FIND-1:0];
generate
    for(index=0;index<SYMBOL_NUMS_TO_FIND;index=index+1) begin
        // 与已知序列混频均带来 COR_MIXER_LATENCY clks延时.
        mixer_strobe #(
            .A_DATA_WIDTH ( LPF_WIDTH ),
            .B_DATA_WIDTH ( LPF_WIDTH ),
            .IMPL_TYPE    ( "LUT"     ),
            .MODE         ( 0         ))
        u_cor_symbol (
            .clk          ( clk                                 ),
            .rst_n        ( rst_n                               ),
            .in_strobe    ( candidate_strobe                    ),
            .ai           ( symbol_i[SYMBOL_NUMS_TO_FIND-1-index] ),
            .aq           ( symbol_q[SYMBOL_NUMS_TO_FIND-1-index] ),
            .bi           ( preamble_known_i[index]             ),
            .bq           ( preamble_known_q[index]             ),

            .out_strobe   (                                     ),
            .oi           ( cor_symbol_i[index]                 ),
            .oq           ( cor_symbol_q[index]                 )
        );
    end
endgenerate

// 带来$clog2(SYMBOL_NUMS_TO_FIND) clks延时
AdderTree #(
    .IMPL_TYPE  ( "DSP"             ),
    .DATA_WIDTH ( MIXER_OUT_WIDTH   ),
    .DATA_TYPE  ( 1                 ),
    .OUT_WIDTH  ( COR_WIDTH         ),
    .LATENCY    ( 1                 ),
    .DATA_NUM   ( SYMBOL_NUMS_TO_FIND   ))
 u_AdderTree_corr_i (
    .clk       ( clk                ),
    .in_data   ( cor_symbol_i       ),

    .sum_out   ( correlation_i      )
);AdderTree #(
    .IMPL_TYPE  ( "DSP"             ),
    .DATA_WIDTH ( MIXER_OUT_WIDTH   ),
    .DATA_TYPE  ( 1                 ),
    .OUT_WIDTH  ( COR_WIDTH         ),
    .LATENCY    ( 1                 ),
    .DATA_NUM   ( SYMBOL_NUMS_TO_FIND   ))
 u_AdderTree_corr_q (
    .clk       ( clk                ),
    .in_data   ( cor_symbol_q       ),

    .sum_out   ( correlation_q      )
);


// strobe与相关数据统一带来 COR_LATENCY clks延时.
delay #(
    .DATA_WIDTH ( 1           ),
    .DELAY_CLK  ( COR_LATENCY ),
    .IMPL_TYPE  ( 0           ))
 u_delay_correlation_strobe (
    .clk        ( clk                 ),
    .data_in    ( candidate_strobe    ),

    .data_out   ( correlation_strobe  )
);

endmodule
