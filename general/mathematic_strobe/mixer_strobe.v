// 总共7个延迟
module mixer_strobe #(
    parameter A_DATA_WIDTH = 16,
    parameter B_DATA_WIDTH = 16,
    parameter IMPL_TYPE = "LUT",
    parameter MODE = 1              // 0:f=a-b  1:f=a+b
) (
    input wire clk,
    input wire rst_n,                 // 降低功率
    input wire in_strobe,
    input wire [A_DATA_WIDTH-1:0] ai, // A 的实部 (I)
    input wire [A_DATA_WIDTH-1:0] aq, // A 的虚部 (Q)
    input wire [B_DATA_WIDTH-1:0] bi, // B 的实部 (I)
    input wire [B_DATA_WIDTH-1:0] bq, // B 的虚部 (Q)

    output wire out_strobe,
    output reg [A_DATA_WIDTH+B_DATA_WIDTH-1:0] oi, // 输出实部 (I)
    output reg [A_DATA_WIDTH+B_DATA_WIDTH-1:0] oq  // 输出虚部 (Q)
);

localparam OUT_WIDTH = A_DATA_WIDTH + B_DATA_WIDTH;
localparam STROBE_DELAY = 7;
localparam RESET_FLUSH_W = (STROBE_DELAY <= 1) ? 1 : $clog2(STROBE_DELAY + 1);
localparam [RESET_FLUSH_W-1:0] STROBE_DELAY_COUNT = STROBE_DELAY;

// Stage registers
reg [A_DATA_WIDTH-1:0] ai_r, aq_r;
reg [B_DATA_WIDTH-1:0] bi_r, bq_r;

reg [RESET_FLUSH_W-1:0] reset_flush_cnt;
wire strobe_pipe_ready;
wire active_strobe;

assign strobe_pipe_ready = (reset_flush_cnt == STROBE_DELAY_COUNT);
assign active_strobe = in_strobe & strobe_pipe_ready;

// reset释放后等待delay管线灌入0，避免无复位delay输出未知strobe。
always @(posedge clk) begin
    if (!rst_n) begin
        reset_flush_cnt <= {RESET_FLUSH_W{1'b0}};
    end else if (reset_flush_cnt < STROBE_DELAY_COUNT) begin
        reset_flush_cnt <= reset_flush_cnt + 1'b1;
    end
end

// Products (32-bit signed)
wire [OUT_WIDTH-1:0] p0; // ai * bi
wire [OUT_WIDTH-1:0] p1; // aq * bq
wire [OUT_WIDTH-1:0] p2; // aq * bi
wire [OUT_WIDTH-1:0] p3; // ai * bq

// arithemetic stage1, 带来三个延迟
multiplier #(
    .A_WIDTH   ( A_DATA_WIDTH   ),      // a输入位宽
    .B_WIDTH   ( B_DATA_WIDTH   ),      // b输入位宽
    .A_TYPE    ( 1    ),                // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),                // 1:有符号数 0:无符号数
    .LATENCY   ( 3    ),                // 总延迟
    .OUT_WIDTH ( OUT_WIDTH ))           // 输出位宽,取低位
 multi_aibi (
    .clk                     ( clk                  ),
    .A                       ( ai_r    [A_DATA_WIDTH-1:0]   ),
    .B                       ( bi_r    [B_DATA_WIDTH-1:0]   ),

    .P                       ( p0    [OUT_WIDTH-1:0] )
);

multiplier #(
    .A_WIDTH   ( A_DATA_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( B_DATA_WIDTH   ),     // b输入位宽
    .A_TYPE    ( 1    ),               // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3    ),     // 总延迟
    .OUT_WIDTH ( OUT_WIDTH ))     // 输出位宽,取低位
 multi_aqbq (
    .clk                     ( clk                  ),
    .A                       ( aq_r    [A_DATA_WIDTH-1:0]   ),
    .B                       ( bq_r    [B_DATA_WIDTH-1:0]   ),

    .P                       ( p1    [OUT_WIDTH-1:0] )
);

multiplier #(
    .A_WIDTH   ( A_DATA_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( B_DATA_WIDTH   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3    ),     // 总延迟
    .OUT_WIDTH ( OUT_WIDTH ))     // 输出位宽,取低位
 multi_aqbi (
    .clk                     ( clk                  ),
    .A                       ( aq_r    [A_DATA_WIDTH-1:0]   ),
    .B                       ( bi_r    [B_DATA_WIDTH-1:0]   ),

    .P                       ( p2    [OUT_WIDTH-1:0] )
);

multiplier #(
    .A_WIDTH   ( A_DATA_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( B_DATA_WIDTH   ),     // b输入位宽
    .A_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 1    ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3    ),     // 总延迟
    .OUT_WIDTH ( OUT_WIDTH ))     // 输出位宽,取低位
 multi_aibq (
    .clk                     ( clk                  ),
    .A                       ( ai_r    [A_DATA_WIDTH-1:0]   ),
    .B                       ( bq_r    [B_DATA_WIDTH-1:0]   ),

    .P                       ( p3    [OUT_WIDTH-1:0] )
);


// arithemetic stage2, 带来两个延迟
wire [OUT_WIDTH-1:0] oi_wire;
wire [OUT_WIDTH-1:0] oq_wire;
generate
    if (MODE == 0) begin        // 频率相减
        // sin(α-β) = sinαcosβ - cosαsinβ
        Subtracter #(
            .IMPL_TYPE ( IMPL_TYPE ),   //string "DSP" / "LUT"
            .A_WIDTH   ( OUT_WIDTH   ),   
            .B_WIDTH   ( OUT_WIDTH   ),
            .A_TYPE    ( 1    ),   //1: signed 0: unsigned
            .B_TYPE    ( 1    ),   //1: signed 0: unsigned
            .OUT_WIDTH ( OUT_WIDTH   ),   
            .LATENCY   ( 2   ))
        u_Subtracter (
            .clk                     ( clk                  ),
            .A                       ( p2    [OUT_WIDTH-1:0]   ),
            .B                       ( p3    [OUT_WIDTH-1:0]   ),

            .SUM                     ( oq_wire  [OUT_WIDTH-1:0] )
        );
        // cos(α-β) = cosαcosβ + sinαsinβ
        Adder #(
            .IMPL_TYPE ( IMPL_TYPE ),   //string "DSP" / "LUT"
            .A_WIDTH   ( OUT_WIDTH   ),   
            .B_WIDTH   ( OUT_WIDTH   ),
            .A_TYPE    ( 1    ),    //1: signed 0: unsigned
            .B_TYPE    ( 1    ),    //1: signed 0: unsigned
            .OUT_WIDTH ( OUT_WIDTH ),   
            .LATENCY   ( 2   ))
        u_Adder (
            .clk                     ( clk                  ),
            .A                       ( p0    [OUT_WIDTH-1:0]   ),
            .B                       ( p1    [OUT_WIDTH-1:0]   ),

            .SUM                     ( oi_wire  [OUT_WIDTH-1:0] )
        );
    end else begin
        // sin(α+β) = sinαcosβ + cosαsinβ
        Adder #(
            .IMPL_TYPE ( IMPL_TYPE ),   //string "DSP" / "LUT"
            .A_WIDTH   ( OUT_WIDTH   ),   
            .B_WIDTH   ( OUT_WIDTH   ),
            .A_TYPE    ( 1    ),    //1: signed 0: unsigned
            .B_TYPE    ( 1    ),    //1: signed 0: unsigned
            .OUT_WIDTH ( OUT_WIDTH ),   
            .LATENCY   ( 2   ))
        u_Adder (
            .clk                     ( clk                  ),
            .A                       ( p2    [OUT_WIDTH-1:0]   ),
            .B                       ( p3    [OUT_WIDTH-1:0]   ),

            .SUM                     ( oq_wire  [OUT_WIDTH-1:0] )
        );
        // cos(α+β) = cosαcosβ - sinαsinβ
        Subtracter #(
            .IMPL_TYPE ( IMPL_TYPE ),   //string "DSP" / "LUT"
            .A_WIDTH   ( OUT_WIDTH   ),   
            .B_WIDTH   ( OUT_WIDTH   ),
            .A_TYPE    ( 1    ),   //1: signed 0: unsigned
            .B_TYPE    ( 1    ),   //1: signed 0: unsigned
            .OUT_WIDTH ( OUT_WIDTH ),   
            .LATENCY   ( 2   ))
        u_Subtracter (
            .clk                     ( clk                  ),
            .A                       ( p0    [OUT_WIDTH-1:0]   ),
            .B                       ( p1    [OUT_WIDTH-1:0]   ),

            .SUM                     ( oi_wire  [OUT_WIDTH-1:0] )
        );
    end
endgenerate



// Stage 1: latch inputs, 带来一个延迟
always @(posedge clk) begin
    if (!rst_n) begin
        ai_r <= 0; 
        aq_r <= 0; 
        bi_r <= 0; 
        bq_r <= 0;
    end else begin
        if(active_strobe) begin
            ai_r <= ai;
            aq_r <= aq;
            bi_r <= bi;
            bq_r <= bq;
        end
    end
end

// Stage 2: register products, 带来一个延迟
always @(posedge clk) begin
    if (!rst_n) begin
        oi <= 0;
        oq <= 0;
    end else begin
        oi <= oi_wire;
        oq <= oq_wire;
    end
end


wire out_strobe_raw;

assign out_strobe = out_strobe_raw & strobe_pipe_ready;

delay #(
    .DATA_WIDTH ( 1  ),
    .DELAY_CLK  ( STROBE_DELAY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_strobe (
    .clk          ( clk          ),
    .data_in      ( active_strobe ),

    .data_out     ( out_strobe_raw )
);

endmodule
