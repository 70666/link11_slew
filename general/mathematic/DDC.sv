module DDC #(
    parameter DATA_WIDTH = 16,
    parameter DDS_PATTERN_WIDTH = 8,
    parameter DDS_PHASE_WIDTH = 16,
    parameter STANDARD_DDC_PHASE_INC = 4096
) (
    input wire clk,
    input wire rst_n,
    input wire                         data_in_storbe,
    input wire [DATA_WIDTH-1:0] data_in_i,
    input wire [DATA_WIDTH-1:0] data_in_q,
    output wire [DATA_WIDTH+DDS_PATTERN_WIDTH-1:0] zeroif_sync_i,
    output wire [DATA_WIDTH+DDS_PATTERN_WIDTH-1:0] zeroif_sync_q,
    output wire zeroif_sync_strobe
);

// 生成一个2915Hz标准参考波. 有7strobe延时+1clk延时
wire [DDS_PATTERN_WIDTH-1:0] sync_ref_i;
wire [DDS_PATTERN_WIDTH-1:0] sync_ref_q;
    link11_tone_ref_dds #(
        .DATA_WIDTH  ( DDS_PATTERN_WIDTH    ),
        .PHASE_WIDTH ( DDS_PHASE_WIDTH      ),
        .PHASE_INC   ( STANDARD_DDC_PHASE_INC  ))
    u_tone_ref_dds (
        .clk        ( clk                       ),
        .rst_n      ( rst_n                     ),
        .clear      ( ~rst_n                    ),      // 没必要每个消息来时都clear一次, 前后两个消息之间没有必然相位关联
        .in_strobe  ( data_in_storbe         ),
        .ref_strobe (                           ),
        .ref_i      ( sync_ref_i                ),
        .ref_q      ( sync_ref_q                )
    );
// 对齐dds延时
wire mixer_in_strobe;
wire [DATA_WIDTH-1:0] mixer_in_i;
wire [DATA_WIDTH-1:0] mixer_in_q;
    delay #(
        .DATA_WIDTH ( 2*DATA_WIDTH + 1 ),
        .DELAY_CLK  ( 1  ),
        .IMPL_TYPE  ( 0  ))
    u_delay (
        .clk                     ( clk                        ),
        .data_in                 ( {data_in_storbe, data_in_q, data_in_i} ),

        .data_out                ( {mixer_in_strobe, mixer_in_q, mixer_in_i} )
    );

// 下变频
wire mixer_out_strobe;
wire [DATA_WIDTH+DDS_PATTERN_WIDTH-1:0] mixer_out_i;
wire [DATA_WIDTH+DDS_PATTERN_WIDTH-1:0] mixer_out_q;
assign zeroif_sync_strobe = mixer_out_strobe;
assign zeroif_sync_i = mixer_out_i;
assign zeroif_sync_q = mixer_out_q;
mixer_strobe #(
    .A_DATA_WIDTH ( DATA_WIDTH   ),
    .B_DATA_WIDTH ( DDS_PATTERN_WIDTH   ),
    .IMPL_TYPE    ( "LUT"               ),
    .MODE         ( 0                   ))
 u_mixer_strobe (
    .clk                     ( clk                      ),
    .rst_n                   ( rst_n                    ),
    .in_strobe               ( mixer_in_strobe                                   ),
    .ai                      ( mixer_in_i               ),
    .aq                      ( mixer_in_q               ),
    .bi                      ( sync_ref_i               ),
    .bq                      ( sync_ref_q               ),

    .out_strobe              ( mixer_out_strobe         ),
    .oi                      ( mixer_out_i              ),
    .oq                      ( mixer_out_q              )
);
endmodule