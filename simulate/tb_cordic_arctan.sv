`timescale 1ns / 1ps

module tb_cordic_arctan;

localparam integer DATA_WIDTH  = 16;
localparam integer PHASE_WIDTH = 16;
localparam integer TEST_NUM    = 10;

reg clk = 1'b0;
always #5 clk = ~clk;

reg s_axis_cartesian_tvalid = 1'b0;
reg signed [DATA_WIDTH-1:0] sin_data = '0;
reg signed [DATA_WIDTH-1:0] cos_data = '0;

wire [2*DATA_WIDTH-1:0] s_axis_cartesian_tdata;
wire m_axis_dout_tvalid;
wire [PHASE_WIDTH-1:0] m_axis_dout_tdata;

integer send_index = 0;
integer recv_index = 0;
integer timeout_count = 0;

reg signed [15:0] test_sin [0:TEST_NUM-1];
reg signed [15:0] test_cos [0:TEST_NUM-1];
integer test_deg [0:TEST_NUM-1];
reg signed [15:0] expect_phase [0:TEST_NUM-1];

assign s_axis_cartesian_tdata = {sin_data, cos_data};

// Scaled radians: output is approximately angle / pi in signed 16-bit format.
function automatic signed [15:0] deg_to_scaled_phase(input integer deg);
    integer phase_tmp;
begin
    phase_tmp = (deg * 32768) / 180;
    deg_to_scaled_phase = phase_tmp[15:0];
end
endfunction

task automatic set_case(
    input integer index,
    input integer deg,
    input signed [15:0] sin_value,
    input signed [15:0] cos_value
);
begin
    test_deg[index] = deg;
    test_sin[index] = sin_value;
    test_cos[index] = cos_value;
    expect_phase[index] = deg_to_scaled_phase(deg);
end
endtask

initial begin
    // SignedFraction input vectors use about half scale to avoid boundary clipping.
    set_case(0,    0,  16'sd0/2,      16'sd16384/2);
    set_case(1,   30,  16'sd8192/2,   16'sd14189/2);
    set_case(2,   45,  16'sd11585/2,  16'sd11585/2);
    set_case(3,   60,  16'sd14189/2,  16'sd8192/2);
    set_case(4,   90,  16'sd16384/2,  16'sd0/2);
    set_case(5,  135,  16'sd11585/2, -16'sd11585/2);
    set_case(6,  180,  16'sd0/2,     -16'sd16384/2);
    set_case(7, -135, -16'sd11585/2, -16'sd11585/2);
    set_case(8,  -90, -16'sd16384/2,  16'sd0/2);
    set_case(9,  -45, -16'sd11585/2,  16'sd11585/2);

    $display("CORDIC arctan behavior check");
    $display("TDATA = {imag/sin[31:16], real/cos[15:0]}, phase uses Scaled_Radians");
    $display("expect_hex is a reference value only, IP truncate and 180 degree boundary may differ");

    repeat (5) @(posedge clk);

    while (send_index < TEST_NUM) begin
        @(posedge clk);
        s_axis_cartesian_tvalid <= 1'b1;
        sin_data <= test_sin[send_index];
        cos_data <= test_cos[send_index];
        $display("send[%0d]: deg=%0d sin=%0d cos=%0d expect_hex=%h",
                 send_index,
                 test_deg[send_index],
                 test_sin[send_index],
                 test_cos[send_index],
                 expect_phase[send_index]);
        send_index <= send_index + 1;
    end

    // @(posedge clk);
    s_axis_cartesian_tvalid <= 1'b0;
    sin_data <= '0;
    cos_data <= '0;
end

always @(posedge clk) begin
    if (m_axis_dout_tvalid) begin
        $display("recv[%0d]: dout_hex=%h dout_signed=%0d ref_deg=%0d ref_hex=%h",
                 recv_index,
                 m_axis_dout_tdata,
                 $signed(m_axis_dout_tdata),
                 test_deg[recv_index],
                 expect_phase[recv_index]);
        recv_index <= recv_index + 1;
        timeout_count <= 0;
    end else if (send_index >= TEST_NUM) begin
        timeout_count <= timeout_count + 1;
    end
end

initial begin
    wait (recv_index == TEST_NUM);
    repeat (5) @(posedge clk);
    $display("CORDIC arctan behavior check finished");
    $finish;
end

initial begin
    wait (timeout_count > 200);
    $display("ERROR: timeout waiting for CORDIC arctan output");
    $finish;
end

// cordic_arctan latency is decided by IP Pipelining_Mode and Output_Width.
cordic_arctan u_cordic_arctan (
    .aclk(clk),
    .s_axis_cartesian_tvalid(s_axis_cartesian_tvalid),
    .s_axis_cartesian_tdata(s_axis_cartesian_tdata),
    .m_axis_dout_tvalid(m_axis_dout_tvalid),
    .m_axis_dout_tdata(m_axis_dout_tdata)
);

wire [15:0] sin_d, cos_d;
delay #(
    .DATA_WIDTH ( 32 ),
    .DELAY_CLK  ( 20  ),
    .IMPL_TYPE  ( 0  ))
 u_delay (
    .clk                     ( clk                        ),
    .data_in                 ( s_axis_cartesian_tdata ),

    .data_out                ( {sin_d, cos_d} )
);
endmodule
