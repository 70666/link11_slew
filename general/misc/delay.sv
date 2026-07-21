module delay #(
    parameter DATA_WIDTH = 3,
    parameter DELAY_CLK = 10,
    parameter IMPL_TYPE = 0         // 0: FF  2: SRL
) (
    input wire clk,
    input wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out
);


generate
    if(DELAY_CLK == 0) begin
        assign data_out = data_in;
    end else begin
        if(IMPL_TYPE == 0) begin
            (* SHREG_EXTRACT = "NO" *)
            reg [DATA_WIDTH-1:0] data_ff [DELAY_CLK-1:0] ;

            integer i;
            always@(posedge clk) begin
                data_ff[0] <= data_in;
                for(i = 0; i < DELAY_CLK - 1; i = i + 1)begin
                    data_ff[i + 1] <= data_ff[i];
                end
            end
            assign data_out = data_ff[DELAY_CLK-1];
        end 
        else if(IMPL_TYPE == 2) begin
            (* SHREG_EXTRACT = "YES" *)
            reg [DATA_WIDTH-1:0] data_ff [DELAY_CLK-1:0] ;

            integer i;
            always@(posedge clk) begin
                data_ff[0] <= data_in;
                for(i = 0; i < DELAY_CLK - 1; i = i + 1)begin
                    data_ff[i + 1] <= data_ff[i];
                end
            end
            assign data_out = data_ff[DELAY_CLK-1];
        end else begin
            $error("no type match for delay_type 1");
        end
    end
endgenerate



endmodule