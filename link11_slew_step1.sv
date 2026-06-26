module link11_slew_step1 #(
    parameter LPF_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter WINDOW_NUM = 16,                  // 一个符号对应采样点个数
    parameter DDS_PATTERN_WIDTH = 16,
    parameter DDS_PHASE_WIDTH   = 16,
    parameter STANDARD_1800_PHASE_INC = 1600    // 16bit, 1800 * 65536 / sample clk freq
) (
    input wire clk,
    input wire rst_n,
    input wire signal_if_strobe,
    input wire [DATA_WIDTH-1:0] signal_if_i, signal_if_q,
    input wire [2*LPF_WIDTH-1:0] envelope_detection,
    output wire envelope,
    output wire [LPF_WIDTH-1:0] signal_lpf_envelope_i, signal_lpf_envelope_q,
    output wire signal_lpf_envelope_strobe
);

// 1800Hz DDC 得到只有频偏, 1800Hz不旋转的基带信号
localparam DDC_WIDTH = DDS_PATTERN_WIDTH + DDS_PHASE_WIDTH;
wire [DDC_WIDTH-1:0] zeroif_sync_i, zeroif_sync_q;
wire zeroif_sync_strobe;
DDC #(
    .DATA_WIDTH             ( DATA_WIDTH             ),
    .DDS_PATTERN_WIDTH      ( DDS_PATTERN_WIDTH      ),
    .DDS_PHASE_WIDTH        ( DDS_PHASE_WIDTH        ),
    .STANDARD_DDC_PHASE_INC ( STANDARD_1800_PHASE_INC ))
 u_DDC (
    .clk                     ( clk                  ),
    .rst_n                   ( rst_n                ),
    .data_in_storbe          ( signal_if_strobe     ),
    .data_in_i               ( signal_if_i          ),
    .data_in_q               ( signal_if_q          ),

    .zeroif_sync_i           ( zeroif_sync_i        ),
    .zeroif_sync_q           ( zeroif_sync_q        ),
    .zeroif_sync_strobe      ( zeroif_sync_strobe   )
);

// 低通滤波, 滤除高频 (暂时跳过)
wire [LPF_WIDTH-1:0] signal_lpf_i, signal_lpf_q;
wire signal_lpf_strobe;
assign signal_lpf_i = zeroif_sync_i[DDC_WIDTH-1-:LPF_WIDTH];
assign signal_lpf_q = zeroif_sync_q[DDC_WIDTH-1-:LPF_WIDTH];
assign signal_lpf_strobe = zeroif_sync_strobe;

// 包络检波, 获取包络
envelope_detector_strobe #(
    .DATA_WIDTH             ( LPF_WIDTH             ),
    .BIT_ENVELOPE_DETECTION ( 2*LPF_WIDTH           ),
    .DETECTION_CLOCK_NUM    ( 16                    ),
    .DETECTION_HIGH_NUM     ( 12                    ),
    .CHANNEL_NUM            ( 1                     ))
 uenvelope_detector_strobe (
    .clk                     ( clk                              ),
    .clock_enable            ( signal_lpf_strobe                ),
    .rst_n                   ( rst_n                            ),
    .signal_in               ( {signal_lpf_q, signal_lpf_i}     ),
    .envelope_detection0     ( envelope_detection               ),
    .envelope_detection1     ( envelope_detection               ),

    .envelope                ( envelope                         ),
    .clock_enable_out        ( signal_lpf_envelope_strobe       ),
    .signal_out              ({signal_lpf_envelope_q, signal_lpf_envelope_i})
);

endmodule