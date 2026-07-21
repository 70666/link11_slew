module link11_slew_step3_phase_corr_gen#(
    parameter LPF_WIDTH = 16,
    parameter CORDIC_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire phase_cor_est_strobe,
    input wire [CORDIC_WIDTH-2:0] phase_cor_est_i, phase_cor_est_q,
    input wire symbol_aligned_strobe,
    input wire [LPF_WIDTH-1:0] symbol_aligned_i, symbol_aligned_q,
    output wire [15:0] phase_corr_dds_i, phase_corr_dds_q,
    output reg correcting = 0   // DDS生成信号是否有效的标识, 允许读ram
);

localparam DDS_LATENCY_STROBE = 7;

localparam CORDIC_WIDTH_REAL = (CORDIC_WIDTH % 8 == 0)? CORDIC_WIDTH : (CORDIC_WIDTH / 8 + 1) * 8;
localparam MIXER_WIDTH = LPF_WIDTH + 16;

wire [2*CORDIC_WIDTH_REAL-1:0] cordic_cartesian_tdata;
wire cordic_cartesian_tvalid;
assign cordic_cartesian_tdata[CORDIC_WIDTH_REAL-1:0]                    = { {(CORDIC_WIDTH_REAL-CORDIC_WIDTH){1'b0}}, phase_cor_est_i[CORDIC_WIDTH-2], phase_cor_est_i};
assign cordic_cartesian_tdata[2*CORDIC_WIDTH_REAL-1:CORDIC_WIDTH_REAL]  = { {(CORDIC_WIDTH_REAL-CORDIC_WIDTH){1'b0}}, phase_cor_est_q[CORDIC_WIDTH-2], phase_cor_est_q};

assign cordic_cartesian_tvalid = phase_cor_est_strobe;


// cordic_cartesian_tvalid -> m_axis_dout_tvalid 20 clks
wire m_axis_dout_tvalid;
wire [CORDIC_WIDTH-1:0] m_axis_dout_tdata;              // 最大值(2**(CORDIC_WIDTH-3)-1), 最小值-(2**(CORDIC_WIDTH-3))
wire [CORDIC_WIDTH-3:0] phase_out;                      // m_axis_dout_tdata * (2 << DDS_PHASE_WIDTH) / (2**(CORDIC_WIDTH-2))
assign phase_out = m_axis_dout_tdata[CORDIC_WIDTH-3:0]; // 高2bit是额外的符号位
cordic_arctan u_cordic_arctan (
    .aclk(clk),
    .s_axis_cartesian_tvalid(cordic_cartesian_tvalid),
    .s_axis_cartesian_tdata(cordic_cartesian_tdata),
    .m_axis_dout_tvalid(m_axis_dout_tvalid),
    .m_axis_dout_tdata(m_axis_dout_tdata)
);

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
                cnt_symbol_strobe <= 0;
                correcting <= 0;
            end 
            IN_CORR:begin
                if(demod_done) begin
                    state <= IDLE;
                end else begin
                    state <= IN_CORR;
                end
                if(symbol_aligned_strobe) begin
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


// symbol_aligned_strobe -> m_axis_data_tdata 1 clk
wire [31:0] m_axis_data_tdata;
assign phase_corr_dds_q = m_axis_data_tdata[31:16];
assign phase_corr_dds_i = m_axis_data_tdata[15:0];
dds_lut_p14a16 dds_lut_p14a16 (
    .aclk(clk),                                     // input wire aclk
    .aclken(symbol_aligned_strobe),                 // input wire aclken
    .s_axis_config_tvalid(1'b1),                    // input wire s_axis_config_tvalid
    .s_axis_config_tdata(phase_out),                // input wire [15 : 0] s_axis_config_tdata
    .m_axis_data_tvalid(m_axis_data_tvalid),        // output wire m_axis_data_tvalid
    .m_axis_data_tdata(m_axis_data_tdata)           // output wire [31 : 0] m_axis_data_tdata
);


endmodule
