// 格雷码编码格式
module qpsk_decoder #(
    parameter DATA_WIDTH = 16
) (
    input wire clk,
    input wire strobe,
    input wire [DATA_WIDTH-1:0] i, q,
    output reg [1:0] decode_out,
    output reg decode_strobe
);

wire [DATA_WIDTH-1:0] abs_i, abs_q;
assign abs_i = i[DATA_WIDTH-1]? (~i + 1) : i;
assign abs_q = q[DATA_WIDTH-1]? (~q + 1) : q;

always @(posedge clk ) begin
    if(strobe) begin
        if(abs_i > abs_q) begin         // x轴
            if(i[DATA_WIDTH-1])         // 180°
                decode_out <= 2'b11;
            else                        // 0°
                decode_out <= 2'b00;
        end else begin                  // y轴
            if(q[DATA_WIDTH-1])
                decode_out <= 2'b10;    // 270°
            else
                decode_out <= 2'b01;    // 90°
        end
        decode_strobe <= 1;
    end else begin
        decode_strobe <= 0;
    end
end
endmodule