// 输出为低 OUT_WIDTH 位。
// 总延迟（理论）： LATENCY * $clog2(DATA_NUM)

module AdderTree #(
    parameter IMPL_TYPE = "LUT",      // 直接传给底层 Adder
    parameter DATA_WIDTH = 16,        // 基本输入位宽（每个输入）
    parameter DATA_TYPE  = 0,         // 1: signed, 0: unsigned -> 传给 Adder 的 A_TYPE/B_TYPE
    parameter OUT_WIDTH  = 16,        // 最终输出截取的低多少位
    parameter LATENCY    = 1,         // 直接传给底层 Adder
    parameter DATA_NUM   = 8          // 要相加的输入个数
) (
    input  wire clk,
    input  wire [DATA_WIDTH-1:0] in_data [DATA_NUM-1:0],
    output wire [OUT_WIDTH-1:0]  sum_out
);
// 加法器层级
    localparam LEVEL = $clog2(DATA_NUM);
    localparam MAX_NUM = 2**LEVEL;
    localparam MAX_WIDTH = DATA_WIDTH + LEVEL;

wire [MAX_WIDTH-1:0] wire_level [LEVEL:0] [MAX_NUM-1:0];

// 输入补齐符号
genvar s;
generate
    for(s = 0; s < MAX_NUM; s = s + 1) begin
        if(s < DATA_NUM) begin
            if(DATA_TYPE == 0)  // 无符号数
                assign wire_level[0][s] = { {(MAX_WIDTH-DATA_WIDTH){1'b0}} , in_data[s]};
            else    
                assign wire_level[0][s] = { {(MAX_WIDTH-DATA_WIDTH){in_data[s][DATA_WIDTH-1]}}, in_data[s]};
        end else begin
            assign wire_level[0][s] = 0;
        end
    end
endgenerate 

genvar m;
generate
    for(s = 0; s < LEVEL; s = s + 1) begin
        // 当前层的加法数量
        localparam int LEVEL_DATA_NUM = (MAX_NUM >> s);
        for(m = 0; m < LEVEL_DATA_NUM / 2; m = m + 1) begin
            Adder #(
                .IMPL_TYPE ( IMPL_TYPE ),  
                .A_WIDTH   ( MAX_WIDTH   ),   
                .B_WIDTH   ( MAX_WIDTH   ),
                .A_TYPE    ( DATA_TYPE    ),   
                .B_TYPE    ( DATA_TYPE    ),   
                .OUT_WIDTH ( MAX_WIDTH ),   
                .LATENCY   ( LATENCY   ))
            Adder (
                .clk        ( clk                  ),
                .A          ( wire_level[s][2*m]     ),
                .B          ( wire_level[s][2*m+1]   ),

                .SUM        ( wire_level[s+1][m]      )
            );
        end
    end
endgenerate

// 输出结果
assign sum_out = wire_level[LEVEL][0];

endmodule
