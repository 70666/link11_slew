module tb_dds_p14a16 (
);

reg clk = 0;
always#5 clk = ~clk;
reg symbol_aligned_strobe = 0;
reg [13:0] phase_out = 0;
initial begin
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 1033;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 2066;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
    repeat(10) @(posedge clk) ;
    symbol_aligned_strobe = 1;
    phase_out = 3099;
    repeat(1) @(posedge clk) ;
    symbol_aligned_strobe = 0;
end
wire m_axis_data_tvalid;
wire [31:0] m_axis_data_tdata;
dds_lut_p14a16 dds_lut_p14a16 (
    .aclk(clk),                                     // input wire aclk
    .aclken(symbol_aligned_strobe),                 // input wire aclken
    .s_axis_config_tvalid(1'b1),                    // input wire s_axis_config_tvalid
    .s_axis_config_tdata({2'b0, phase_out}),        // input wire [15 : 0] s_axis_config_tdata
    .m_axis_data_tvalid(m_axis_data_tvalid),        // output wire m_axis_data_tvalid
    .m_axis_data_tdata(m_axis_data_tdata)           // output wire [31 : 0] m_axis_data_tdata
);
endmodule