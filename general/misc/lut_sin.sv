// 在"RUNTIME"模式下, 本模块固定1个输入clk延时 + 7个样本延时即strobe延时
// 7个样本延时不是7个clk延时, 而是输出的相位相对于输入的相位的延时
module lut_sin #(
    parameter WORKING_MODE = "PRELOAD", // 工作模式, "PRELOAD" "RUNTIME"
    parameter PHASE_WIDTH = 16,         // LUT相位位宽,   最大为16 和DDSip核设置保持一致
    parameter DATA_WIDTH = 16,          // 数据输出位宽,  最大为16 和DDSip核设置保持一致
    parameter PRELOAD_LENGTH = 100      // 预加载数组长度
) (
    input wire clk,
    input wire rst_n,
    input wire phase_strobe,
    input wire [PHASE_WIDTH-1:0] phase,
    // 实时端口
    output data_strobe,
    output [DATA_WIDTH-1:0] sin,            // 实时sin输出
    output [DATA_WIDTH-1:0] cos,            // 实时cos输出
    // 预加载端口, 复位后仅需PRELOAD_LENGTH个时钟即可填充完毕, 填充时间可以忽略不计
    output reg [DATA_WIDTH-1:0] sin_preload [PRELOAD_LENGTH-1:0],
    output reg [DATA_WIDTH-1:0] cos_preload [PRELOAD_LENGTH-1:0]
);
    
wire [15:0] phase_e;
localparam DDS_LATENCY = 7;
// dds查找表输出延时为7
reg s_axis_phase_tvalid;
reg [15 : 0] s_axis_phase_tdata;
wire m_axis_data_tvalid;
wire [31 : 0] m_axis_data_tdata;
dds_lut_sin u_dds_lut_sin (
    .aclk(clk),                                 // input wire aclk
    .aclken(rst_n),                            // input wire aclken
    .s_axis_phase_tvalid(s_axis_phase_tvalid),  // input wire s_axis_phase_tvalid
    .s_axis_phase_tdata(s_axis_phase_tdata),    // input wire [15 : 0] s_axis_phase_tdata
    .m_axis_data_tvalid(m_axis_data_tvalid),    // output wire m_axis_data_tvalid
    .m_axis_data_tdata(m_axis_data_tdata)       // output wire [31 : 0] m_axis_data_tdata
);


generate
    if(WORKING_MODE == "PRELOAD") begin
        localparam PRELOAD_INC = 65536 / PRELOAD_LENGTH;
        reg [$clog2(PRELOAD_LENGTH)-1:0] cnt_preload = 0;
        wire [$clog2(PRELOAD_LENGTH)-1:0] index;
        reg [PHASE_WIDTH-1:0] phase_preload = 0;

        always_ff @( posedge clk ) begin
            if(~rst_n) begin
                cnt_preload <= 0;
                phase_preload <= 0;
                s_axis_phase_tvalid <= 0;
                s_axis_phase_tdata <= 0;
            end else begin
                s_axis_phase_tvalid <= 1;
                s_axis_phase_tdata  <= phase_preload;
                if(cnt_preload < PRELOAD_LENGTH - 1 && s_axis_phase_tvalid) begin
                    cnt_preload <= cnt_preload + 1;
                    phase_preload <= phase_preload + PRELOAD_INC;
                end else begin
                    cnt_preload <= cnt_preload;
                    phase_preload <= phase_preload;
                end
                cos_preload[index] <= m_axis_data_tdata[15-:DATA_WIDTH];
                sin_preload[index] <= m_axis_data_tdata[31-:DATA_WIDTH];
            end
        end

        delay #(
            .DATA_WIDTH ( $clog2(PRELOAD_LENGTH) ),
            .DELAY_CLK  ( DDS_LATENCY + 1   ),
            .IMPL_TYPE  ( 2                 ))
        u_delay (
            .clk                     ( clk          ),
            .data_in                 ( cnt_preload  ),

            .data_out                ( index        )
        );

    end
endgenerate


generate
    if(WORKING_MODE == "RUNTIME") begin
        assign sin = m_axis_data_tdata[31-:DATA_WIDTH];
        assign cos = m_axis_data_tdata[15-:DATA_WIDTH];
        assign data_strobe = m_axis_data_tvalid;
        always_ff @( posedge clk ) begin 
            if(~rst_n) begin
                s_axis_phase_tvalid <= 0;
                s_axis_phase_tdata  <= 0;
            end else begin
                s_axis_phase_tvalid <= phase_strobe;
                s_axis_phase_tdata  <= phase;
            end
        end
    end
endgenerate

endmodule