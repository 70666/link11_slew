module normalize #(
    parameter DATA_WIDTH_IN = 32,
    parameter DATA_WIDTH_OUT = 16
) (
    input wire clk,
    input wire rst_n,
    input wire data_in_strobe,
    input wire [DATA_WIDTH_IN-1:0] data_in_i, data_in_q,
    output reg data_out_strobe,
    output reg [DATA_WIDTH_OUT-1:0] data_out_i, data_out_q
);

reg normalizing;
wire data_normalized;

reg [DATA_WIDTH_IN-1:0] data_shift_i, data_shift_q;

assign data_normalized =
    ((data_shift_i != 0) && (data_shift_i[DATA_WIDTH_IN-1] != data_shift_i[DATA_WIDTH_IN-2])) ||
    ((data_shift_q != 0) && (data_shift_q[DATA_WIDTH_IN-1] != data_shift_q[DATA_WIDTH_IN-2])) ||
    ((data_shift_i == 0) && (data_shift_q == 0));

always @(posedge clk ) begin
    if(~rst_n) begin
        normalizing <= 0;
        data_out_strobe <= 0;
        data_shift_i <= 0;
        data_shift_q <= 0;
        data_out_i <= 0;
        data_out_q <= 0;
    end else begin
        if(data_in_strobe) begin
            data_shift_i <= data_in_i;
            data_shift_q <= data_in_q;
            normalizing <= 1;
        end else if(normalizing) begin
            if(data_normalized) begin
                normalizing <= 0;
            end else begin
                data_shift_i <= data_shift_i << 1;
                data_shift_q <= data_shift_q << 1;
            end
        end 
        if(data_normalized && normalizing) begin
            data_out_strobe <= 1;
            data_out_i <= data_shift_i[DATA_WIDTH_IN-1-:DATA_WIDTH_OUT];
            data_out_q <= data_shift_q[DATA_WIDTH_IN-1-:DATA_WIDTH_OUT];
        end else begin
            data_out_strobe <= 0;
        end
    end
end
    
endmodule