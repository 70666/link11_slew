module link11_slew_step5_samples_to_symbol #(
    parameter LPF_WIDTH = 16,
    parameter SYMBOL_DATA_WIDTH = 32,
    parameter ADDER_IMPL_TYPE = "DSP",
    parameter ADDER_LATENCY = 2,
    parameter WINDOW_NUM_WIDTH = 6,
    parameter WINDOW_NUM = 16,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 16
) (
    input wire                  clk,
    input wire                  rst_n,
    input wire                  preamble_aligned_start,
    input wire [LPF_WIDTH-1:0]  preamble_aligned_data_i,
    input wire [LPF_WIDTH-1:0]  preamble_aligned_data_q,
    input wire                  preamble_aligned_probe,
    output reg                  symbol_strobe,
    output reg [SYMBOL_DATA_WIDTH-1:0] symbol_i, symbol_q
);
    // 一个symbol内的累加器
wire adder_out_strobe;
wire [SYMBOL_DATA_WIDTH-1:0] adder_out_i, adder_out_q;
reg [SYMBOL_DATA_WIDTH-1:0] adder_temp_i, adder_temp_q;
Adder_strobe #(
    .IMPL_TYPE ( "LUT"              ),  
    .A_WIDTH   ( LPF_WIDTH          ),   
    .B_WIDTH   ( SYMBOL_DATA_WIDTH  ),
    .A_TYPE    ( 1                  ),   
    .B_TYPE    ( 1                  ),   
    .OUT_WIDTH ( SYMBOL_DATA_WIDTH  ),   
    .LATENCY   ( ADDER_LATENCY      ))
 u_Adder_sample_i (
    .clk                     ( clk                      ),
    .data_in_strobe          ( preamble_aligned_probe   ),
    .A                       ( preamble_aligned_data_i  ),
    .B                       ( adder_temp_i             ),

    .data_out_strobe         ( adder_out_strobe         ),
    .SUM                     ( adder_out_i              )
);Adder_strobe #(
    .IMPL_TYPE ( "LUT"              ),  
    .A_WIDTH   ( LPF_WIDTH          ),   
    .B_WIDTH   ( SYMBOL_DATA_WIDTH  ),
    .A_TYPE    ( 1                  ),   
    .B_TYPE    ( 1                  ),   
    .OUT_WIDTH ( SYMBOL_DATA_WIDTH  ),   
    .LATENCY   ( ADDER_LATENCY      ))
 u_Adder_sample_q (
    .clk                     ( clk                      ),
    .data_in_strobe          ( preamble_aligned_probe   ),
    .A                       ( preamble_aligned_data_q  ),
    .B                       ( adder_temp_q             ),

    .data_out_strobe         (                          ),
    .SUM                     ( adder_out_q              )
);

// 状态机, 计数, 统计
reg [WINDOW_NUM_WIDTH-1:0] cnt_sample;          // 0 ~ WINDOW_NUM - 1
always @(posedge clk ) begin
    if(~rst_n) begin
        cnt_sample <= 0;
    end else if(preamble_aligned_start) begin   // 每次新信号到来时复位
        cnt_sample <= 0;
    end else begin
        if(adder_out_strobe) begin
            if(cnt_sample < WINDOW_NUM - 1)
                cnt_sample <= cnt_sample + 1;
            else
                cnt_sample <= 0;
        end
    end
end

always @(posedge clk ) begin
    if(preamble_aligned_start) begin            // 每次新信号到来时复位
        adder_temp_i <= 0;
        adder_temp_q <= 0;
        symbol_strobe <= 0;
    end else begin
        if(cnt_sample == WINDOW_NUM - 1 && adder_out_strobe) begin
            symbol_i <= adder_temp_i;
            symbol_q <= adder_temp_q;
            adder_temp_i <= 0;
            adder_temp_q <= 0;
            symbol_strobe <= 1;                 // 最后一个加法取出
        end else if(adder_out_strobe) begin
            adder_temp_i <= adder_out_i;
            adder_temp_q <= adder_out_q;
            symbol_strobe <= 0;
        end else begin
            symbol_strobe <= 0;
        end
    end 
end
endmodule