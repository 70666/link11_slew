module edge_detect#(
    parameter NO_LATENCY = 1
)(
    input wire clk,
    input wire flag,
    output wire flag_pos,
    output wire flag_neg
);

reg flag_ff;
reg flag_ff2;
always @(posedge clk ) begin
    flag_ff <= flag;
    flag_ff2 <= flag_ff;
end

generate
    if(NO_LATENCY == 1) begin
        assign flag_pos = (!flag_ff && flag);
        assign flag_neg = (flag_ff && !flag);
    end else begin
        assign flag_pos = (flag_ff && !flag_ff2);
        assign flag_neg = (!flag_ff && flag_ff2);
    end
endgenerate




endmodule