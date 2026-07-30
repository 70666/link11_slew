/*
    symbol_start 后 0 ~ 2*SYMBOL_INTERVAL - 1 为前导码, 有保护, 完成存储后, 不再存储
*/
module freq_estimation#(
    parameter SYMBOL_INTERVAL = 32,                     // 相位作差SYMBOL间隔, 需要是2的指数次方
    parameter DEROT_DATA_WIDTH = 16,
    parameter CORDIC_WIDTH = 32                         // 2*DATA_WIDTH+$clog2(SYMBOL_INTERVAL)-1 > CORDIC_WIDTH
) (
    input wire clk,
    input wire rst_n,
    input wire symbol_start,                            // 复位标志, 每个消息只有一次
    input wire preamble_derot_strobe,                   // 一个symbol只有一个采样点, 这个采样点是所有采样点的平均
    input wire [DEROT_DATA_WIDTH-1:0] preamble_derot_i, // 去掉旋转的前导码
    input wire [DEROT_DATA_WIDTH-1:0] preamble_derot_q, 
    output reg correcting,                              // 告知频率校正信号是否生成, 是否允许ram读出 
    output wire [15:0] phase_corr_dds_i,
    output wire [15:0] phase_corr_dds_q                 // 频偏校准信号, 不需要strobe, 和symbol对齐
);

localparam SYMBOL_INTERVAL_W = $clog2(SYMBOL_INTERVAL);

localparam MIXER_LATENCY = 7;
localparam ADDER_LATENCY = 2;


reg [DEROT_DATA_WIDTH-1:0] symbol_array_i [SYMBOL_INTERVAL-1:0];
reg [DEROT_DATA_WIDTH-1:0] symbol_array_q [SYMBOL_INTERVAL-1:0];
reg [SYMBOL_INTERVAL_W+1:0] array_index;
reg [SYMBOL_INTERVAL_W:0] mixer_index;
reg mixer_phase_diff_strobe;

// 存储前半部分, 并在后半部分到来时, 开始相位作差
always @(posedge clk ) begin
    if(~rst_n || symbol_start) begin
        array_index <= 0;
        mixer_index <= 0;
        mixer_phase_diff_strobe <= 0;
    end else begin
        if(preamble_derot_strobe) begin
            if(array_index < SYMBOL_INTERVAL) begin
                array_index <= array_index + 1;
                symbol_array_i[array_index] <= preamble_derot_i;
                symbol_array_q[array_index] <= preamble_derot_q;
                mixer_phase_diff_strobe <= 0;
            end else if(array_index < 2*SYMBOL_INTERVAL) begin
                array_index <= array_index + 1;
                mixer_phase_diff_strobe <= 1;
                mixer_index <= array_index - SYMBOL_INTERVAL;
            end else begin
                mixer_phase_diff_strobe <= 0;
            end
        end else begin
            mixer_phase_diff_strobe <= 0;
        end
    end
end
    
// 将后32个symbol和前32个symbol分别做混频
localparam PHASE_DIFF_WIDTH = 2*DEROT_DATA_WIDTH - 1;
wire phase_diff_strobe;
wire [PHASE_DIFF_WIDTH-1:0] phase_diff_i, phase_diff_q;
mixer_strobe #(
    .A_DATA_WIDTH ( DEROT_DATA_WIDTH      ),
    .B_DATA_WIDTH ( DEROT_DATA_WIDTH      ),
    .IMPL_TYPE    ( "DSP"               ),
    .MODE         ( 0                   ))
u_phase_diff (
    .clk          ( clk                         ),
    .rst_n        ( rst_n                       ),
    .in_strobe    ( mixer_phase_diff_strobe     ),
    .ai           ( preamble_derot_i                    ),
    .aq           ( preamble_derot_q                    ),
    .bi           ( symbol_array_i[mixer_index] ),
    .bq           ( symbol_array_q[mixer_index] ),

    .out_strobe   ( phase_diff_strobe           ),
    .oi           ( phase_diff_i                ),
    .oq           ( phase_diff_q                )
);

wire [SYMBOL_INTERVAL_W-1:0] phase_index;     // 0 ~...
delay #(
    .DATA_WIDTH ( SYMBOL_INTERVAL_W             ),
    .DELAY_CLK  ( MIXER_LATENCY                 ),
    .IMPL_TYPE  ( 0                             ))
 u_delay_phase_index (
    .clk        ( clk                           ),
    .data_in    ( mixer_index                   ),

    .data_out   ( phase_index                   )
);

reg [PHASE_DIFF_WIDTH-1:0] adder_in_i [SYMBOL_INTERVAL-1:0];
reg [PHASE_DIFF_WIDTH-1:0] adder_in_q [SYMBOL_INTERVAL-1:0];
reg adder_tree_in_done;
always @(posedge clk ) begin
    if(phase_diff_strobe) begin
        adder_in_i[phase_index] <= phase_diff_i;
        adder_in_q[phase_index] <= phase_diff_q;
    end 
    if(phase_index == SYMBOL_INTERVAL - 1 && phase_diff_strobe) begin
        adder_tree_in_done <= 1;
    end else begin
        adder_tree_in_done <= 0;
    end
end

localparam ADDER_OUT_WIDTH = PHASE_DIFF_WIDTH + SYMBOL_INTERVAL_W;
localparam ADDER_TREE_LATENCY = ADDER_LATENCY * SYMBOL_INTERVAL_W;
wire [ADDER_OUT_WIDTH-1:0] sum_out_i, sum_out_q;
AdderTree #(
    .IMPL_TYPE  ( "DSP"  ),
    .DATA_WIDTH ( PHASE_DIFF_WIDTH ),
    .DATA_TYPE  ( 1         ),
    .OUT_WIDTH  ( ADDER_OUT_WIDTH  ),
    .LATENCY    ( ADDER_LATENCY    ),
    .DATA_NUM   ( 32   ))
 u_AdderTree_i (
    .clk      ( clk         ),
    .in_data  ( adder_in_i     ),

    .sum_out  ( sum_out_i     )
);AdderTree #(
    .IMPL_TYPE  ( "DSP"  ),
    .DATA_WIDTH ( PHASE_DIFF_WIDTH ),
    .DATA_TYPE  ( 1                 ),
    .OUT_WIDTH  ( ADDER_OUT_WIDTH   ),
    .LATENCY    ( ADDER_LATENCY     ),
    .DATA_NUM   ( 32                ))
 u_AdderTree_q (
    .clk      ( clk             ),
    .in_data  ( adder_in_q      ),

    .sum_out  ( sum_out_q       )
);

wire adder_done;
delay #(
    .DATA_WIDTH ( 1                    ),
    .DELAY_CLK  ( ADDER_TREE_LATENCY   ),
    .IMPL_TYPE  ( 0                    ))
 u_delay_adder_finished (
    .clk        ( clk                  ),
    .data_in    ( adder_tree_in_done   ),

    .data_out   ( adder_done           )
);

// 将长度裁剪至CORDIC需要的长度
wire normalized;  
wire [CORDIC_WIDTH-2:0] normalized_i;        // 因为CORDIC输入范围[-1, 1], 最高两位必须都是符号位才能确保不溢出
wire [CORDIC_WIDTH-2:0] normalized_q;
normalize #(
    .DATA_WIDTH_IN  ( ADDER_OUT_WIDTH   ),
    .DATA_WIDTH_OUT ( CORDIC_WIDTH-1    ))
 u_normalize (
    .clk                     ( clk              ),
    .rst_n                   ( rst_n            ),
    .data_in_strobe          ( adder_done       ),
    .data_in_i               ( sum_out_i        ),
    .data_in_q               ( sum_out_q        ),

    .data_out_strobe         ( normalized        ),
    .data_out_i              ( normalized_i      ),
    .data_out_q              ( normalized_q      )
);



localparam DDS_LATENCY_STROBE = 7;
// 确保CORDIC_WIDTH 对齐1字节长度
localparam CORDIC_WIDTH_REAL = (CORDIC_WIDTH % 8 == 0)? CORDIC_WIDTH : (CORDIC_WIDTH / 8 + 1) * 8;

reg cordic_cartesian_tvalid;
reg [2*CORDIC_WIDTH_REAL-1:0] cordic_cartesian_tdata;

always @(posedge clk ) begin
    cordic_cartesian_tdata[CORDIC_WIDTH_REAL-1:0]                    <= { {(CORDIC_WIDTH_REAL-CORDIC_WIDTH){1'b0}}, normalized_i[CORDIC_WIDTH-2], normalized_i};
    cordic_cartesian_tdata[2*CORDIC_WIDTH_REAL-1:CORDIC_WIDTH_REAL]  <= { {(CORDIC_WIDTH_REAL-CORDIC_WIDTH){1'b0}}, normalized_q[CORDIC_WIDTH-2], normalized_q};
    cordic_cartesian_tvalid <= normalized;
end

// cordic_cartesian_tvalid -> m_axis_dout_tvalid N clks, 延时随着IP核设置变化较大, 为了方便, 不写死
wire m_axis_dout_tvalid;
wire [CORDIC_WIDTH-1:0] m_axis_dout_tdata;              // 最大值(2**(CORDIC_WIDTH-3)-1), 最小值-(2**(CORDIC_WIDTH-3)) -pi ~ +pi
reg [CORDIC_WIDTH-3:0] phase_out;                       // m_axis_dout_tdata * (2 << DDS_PHASE_WIDTH) / (2**(CORDIC_WIDTH-2))
cordic_arctan u_cordic_arctan (
    .aclk(clk),
    .s_axis_cartesian_tvalid(cordic_cartesian_tvalid),
    .s_axis_cartesian_tdata(cordic_cartesian_tdata),
    .m_axis_dout_tvalid(m_axis_dout_tvalid),
    .m_axis_dout_tdata(m_axis_dout_tdata)
);




// 计数逻辑, 必须让DDS开始生成信号时, 才允许ram读出
localparam IDLE = 0;
localparam IN_CORR = 1;
reg state = 0;

reg [3:0] cnt_symbol_strobe;
always @(posedge clk ) begin
    if(~rst_n) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE:   begin
                if(m_axis_dout_tvalid) begin    // CORIC完成了arctan计算
                    state <= IN_CORR;
                end else begin
                    state <= IDLE;
                end
                if(m_axis_dout_tvalid) begin
                    phase_out <= { {SYMBOL_INTERVAL_W{m_axis_dout_tdata[CORDIC_WIDTH-3]}} , m_axis_dout_tdata[CORDIC_WIDTH-3:SYMBOL_INTERVAL_W] }; // 高2bit是额外的符号位, 还要除以32, 因为是隔32做一次相差
                end else begin
                    phase_out <= 0;
                end
                cnt_symbol_strobe <= 0;
                correcting <= 0;
            end 
            IN_CORR:begin
                if(symbol_start) begin          // 每次一个新信号到来时复位
                    state <= IDLE;
                end else begin
                    state <= IN_CORR;
                end
                if(preamble_derot_strobe) begin
                    if(cnt_symbol_strobe < DDS_LATENCY_STROBE) begin
                        cnt_symbol_strobe <= cnt_symbol_strobe + 1;
                    end else begin
                        cnt_symbol_strobe <= cnt_symbol_strobe;
                    end
                end
                if(cnt_symbol_strobe == DDS_LATENCY_STROBE) begin       // DDS 被pipe rush干净
                    correcting <= 1;
                end
            end
        endcase
    end
end


// preamble_derot_strobe -> m_axis_data_tdata 1 clk
wire [31:0] m_axis_data_tdata;
assign phase_corr_dds_q = m_axis_data_tdata[31:16];
assign phase_corr_dds_i = m_axis_data_tdata[15:0];
dds_phase_correction dds_phase_correction (
    .aclk(clk),                                     // input wire aclk
    .aclken(preamble_derot_strobe),                 // input wire aclken
    .s_axis_config_tvalid(1'b1),                    // input wire s_axis_config_tvalid
    .s_axis_config_tdata(phase_out),                // input wire [15 : 0] s_axis_config_tdata
    .m_axis_data_tvalid(m_axis_data_tvalid),        // output wire m_axis_data_tvalid
    .m_axis_data_tdata(m_axis_data_tdata)           // output wire [31 : 0] m_axis_data_tdata
);
endmodule