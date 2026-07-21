/*
如果 b <= a*T    → 靠近 I 轴    T = 0.4142
如果 a <= b*T    → 靠近 Q 轴
否则             → 靠近 45° 斜线
*/
module psk8_decoder #(
    parameter SAMPLE_WIDTH = 16,
    parameter GRAY_OR_NOT = 1
) (
    input wire clk,
    input wire rst_n,
    input wire [SAMPLE_WIDTH-1:0] sample_i, sample_q,
    input wire sample_strobe,
    output wire [2:0] decode_out,
    output wire decode_strobe
);

    reg in_reg_strobe = 0;
    reg i_sign, q_sign;
    reg [SAMPLE_WIDTH-1:0] abs_i, abs_q;
    always @(posedge clk ) begin
        if(~rst_n) begin
            abs_i <= 0;
            abs_q <= 0;
            i_sign <= 0;
            q_sign <= 0;
        end else begin
            if(sample_strobe) begin
                if(sample_i[SAMPLE_WIDTH]) begin
                    abs_i <= ~sample_i + 1;
                    i_sign <= 1;
                end else begin
                    abs_i <= sample_i;
                    i_sign <= 0; 
                end
                if(sample_q[SAMPLE_WIDTH]) begin
                    abs_q <= ~sample_q + 1;
                    q_sign <= 1;
                end else begin
                    abs_q <= sample_q;
                    q_sign <= 0;
                end
                in_reg_strobe <= 1;
            end else begin
                in_reg_strobe <= 0;
            end
        end
    end

localparam IMPL_TYPE = "DSP";
localparam MULT_LATENCY = 3;
wire [SAMPLE_WIDTH+14:0] aT_full, bT_full;
wire [SAMPLE_WIDTH-1:0] aT, bT;
assign aT = aT_full[SAMPLE_WIDTH+14:15];
assign bT = bT_full[SAMPLE_WIDTH+14:15];
multiplier #(
    .IMPL_TYPE ( IMPL_TYPE    ),     // 实现类型
    .A_WIDTH   ( SAMPLE_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( 15         ),     // b输入位宽
    .A_TYPE    ( 0          ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 0          ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3          ),     // 总延迟, 必须大于0
    .OUT_WIDTH ( SAMPLE_WIDTH + 15 ))     // 输出位宽,取低位
 u_multiplier_aT (
    .clk       ( clk     ),
    .A         ( abs_i   ),
    .B         ( 13573   ),

    .P         ( aT_full )
);
multiplier #(
    .IMPL_TYPE ( IMPL_TYPE    ),     // 实现类型
    .A_WIDTH   ( SAMPLE_WIDTH   ),     // a输入位宽
    .B_WIDTH   ( 15         ),     // b输入位宽
    .A_TYPE    ( 0          ),     // 1:有符号数 0:无符号数
    .B_TYPE    ( 0          ),     // 1:有符号数 0:无符号数
    .LATENCY   ( 3          ),     // 总延迟, 必须大于0
    .OUT_WIDTH ( SAMPLE_WIDTH + 15 ))     // 输出位宽,取低位
 u_multiplier_bT (
    .clk       ( clk     ),
    .A         ( abs_q   ),
    .B         ( 13573   ),

    .P         ( bT_full )
);



// 把符号和strobe对齐乘法器输出的绝对值幅度延时
wire in_reg_strobe_aligned;
wire i_sign_aligned, q_sign_aligned;
delay #(
    .DATA_WIDTH ( SAMPLE_WIDTH ),
    .DELAY_CLK  ( MULT_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_abs_i (
    .clk        ( clk                   ),
    .data_in    ( abs_i                    ),

    .data_out   ( a            )
);
delay #(
    .DATA_WIDTH ( SAMPLE_WIDTH ),
    .DELAY_CLK  ( MULT_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_abs_q (
    .clk        ( clk                   ),
    .data_in    ( abs_q                    ),

    .data_out   ( b            )
);
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( MULT_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_i_sign (
    .clk        ( clk                   ),
    .data_in    ( i_sign                    ),

    .data_out   ( i_sign_aligned            )
);
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( MULT_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_q_sign (
    .clk        ( clk                   ),
    .data_in    ( q_sign                    ),

    .data_out   ( q_sign_aligned            )
);
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( MULT_LATENCY  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_strobe (
    .clk        ( clk                   ),
    .data_in    ( in_reg_strobe         ),

    .data_out   ( in_reg_strobe_aligned )
);

reg [2:0] idx;
reg idx_strobe;
always @(posedge clk ) begin
    if(in_reg_strobe_aligned) begin
        if(~i_sign && ~q_sign) begin
            if(b <= aT) idx <= 0;       // 0
            else if(a <= bT) idx <= 2;  // 90
            else    idx <= 1;           // 45
        end else if(i_sign && ~q_sign) begin
            if(b <= aT) idx <= 4;       // 180
            else if(a <= bT) idx <= 2;  // 90
            else    idx <= 3;           // 135
        end else if(i_sign && q_sign) begin
            if(b <= aT) idx <= 4;       // 180
            else if(a <= bT) idx <= 6;  // 270
            else    idx <= 5;           // 225
        end else begin
            if(b <= aT) idx <= 0;       // 0
            else if(a <= bT) idx <= 6;  // 270
            else    idx <= 7;           // 315
        end
        idx_strobe <= 1;
    end else begin
        idx_strobe <= 0;
    end
end
assign decode_out = idx;
assign decode_strobe = idx_strobe;

endmodule