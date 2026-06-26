`timescale 1ns / 1ps

module cordic_arctan_data_format #(
    parameter IQ_WIDTH = 24,
    parameter CORDIC_WIDTH = 16     // CORDIC IP 输入宽度, 当前 IP 为16
)(
    input wire clk,
    input wire rst_n,
    input wire signed [IQ_WIDTH-1:0] i_in,
    input wire signed [IQ_WIDTH-1:0] q_in,
    input wire iq_in_strobe,
    output reg [2*CORDIC_WIDTH-1:0] cordic_cartesian_tdata,
    output reg cordic_cartesian_tvalid
);

wire signed [CORDIC_WIDTH-1:0] i_cordic;
wire signed [CORDIC_WIDTH-1:0] q_cordic;
reg iq_in_strobe_reg;
reg signed [CORDIC_WIDTH-1:0] i_cordic_reg;
reg signed [CORDIC_WIDTH-1:0] q_cordic_reg;
wire [IQ_WIDTH-1:0] i_norm;
wire [IQ_WIDTH-1:0] q_norm;
wire [$clog2(IQ_WIDTH):0] i_shift_left;
wire [$clog2(IQ_WIDTH):0] q_shift_left;
wire [$clog2(IQ_WIDTH):0] iq_shift_left;

// 计算当前数据最多还能左移多少位, 直到最高两位变成01或10.
function automatic [$clog2(IQ_WIDTH):0] calc_left_shift(input signed [IQ_WIDTH-1:0] data_in);
    integer bit_index;
    reg found_valid_bit;
begin
    calc_left_shift = 0;
    found_valid_bit = 1'b0;
    for(bit_index = IQ_WIDTH-2; bit_index >= 0; bit_index = bit_index - 1) begin
        if((!found_valid_bit) && (data_in[bit_index] != data_in[IQ_WIDTH-1])) begin
            calc_left_shift = IQ_WIDTH - 2 - bit_index;
            found_valid_bit = 1'b1;
        end
    end
end
endfunction

assign i_shift_left = calc_left_shift(i_in);
assign q_shift_left = calc_left_shift(q_in);
assign iq_shift_left = (i_shift_left < q_shift_left) ? i_shift_left : q_shift_left;

assign i_norm = i_in <<< iq_shift_left;
assign q_norm = q_in <<< iq_shift_left;

generate
    if(IQ_WIDTH >= CORDIC_WIDTH) begin : gen_cut_high_bits
        assign i_cordic = i_norm[IQ_WIDTH-1-:CORDIC_WIDTH];
        assign q_cordic = q_norm[IQ_WIDTH-1-:CORDIC_WIDTH];
    end else begin : gen_pad_low_bits
        assign i_cordic = {i_norm, {(CORDIC_WIDTH-IQ_WIDTH){1'b0}}};
        assign q_cordic = {q_norm, {(CORDIC_WIDTH-IQ_WIDTH){1'b0}}};
    end
endgenerate

// 1 clk latency, I/Q use the same left shift and keep tvalid aligned with tdata.
always @(posedge clk) begin
    if(~rst_n) begin
        i_cordic_reg <= 0;
        q_cordic_reg <= 0;
        iq_in_strobe_reg <= 0;
    end else if(iq_in_strobe) begin
        iq_in_strobe_reg <= 1;
        i_cordic_reg <= i_cordic;
        q_cordic_reg <= q_cordic;
    end else begin
        iq_in_strobe_reg <= 0;
    end
    if(~rst_n) begin
        cordic_cartesian_tdata <= 0;
        cordic_cartesian_tvalid <= 1'b0;
    end else if(iq_in_strobe_reg) begin
        cordic_cartesian_tvalid <= 1;
        cordic_cartesian_tdata <= {q_cordic_reg, i_cordic_reg};
    end else begin
        cordic_cartesian_tvalid <= 0;
    end
end

endmodule
