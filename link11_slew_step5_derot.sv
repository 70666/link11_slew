module link11_slew_step5_derot #(
    parameter SYMBOL_DATA_WIDTH = 16,
    parameter DEROT_DATA_WIDTH = 31,
    parameter KNOWN_SEQUENCE_END_SYMBOL = 16,
    parameter PREAMBLE_SYMBOL_NUM = 192,
    parameter SYMBOL_INTERVAL = 32
) (
    input wire clk,
    input wire rst_n,
    input wire symbol_start ,
    input wire symbol_strobe,
    input wire [SYMBOL_DATA_WIDTH-1:0] symbol_i,
    input wire [SYMBOL_DATA_WIDTH-1:0] symbol_q,
    output wire preamble_derot_strobe,
    output wire [DEROT_DATA_WIDTH-1:0] preamble_derot_i, 
    output wire [DEROT_DATA_WIDTH-1:0] preamble_derot_q
);

localparam SYMBOL_INTERVAL_W = $clog2(SYMBOL_INTERVAL);

`include "link11_slew_preamble_iq_wire.vh"
`LINK11_SLEW_PREAMBLE_IQ_WIRE_DECLARE
wire [15:0] preamble_i [PREAMBLE_SYMBOL_NUM-2-KNOWN_SEQUENCE_END_SYMBOL:0];
wire [15:0] preamble_q [PREAMBLE_SYMBOL_NUM-2-KNOWN_SEQUENCE_END_SYMBOL:0];

genvar s;
generate
    for(s = 0; s < PREAMBLE_SYMBOL_NUM - KNOWN_SEQUENCE_END_SYMBOL; s = s + 1) begin
        assign preamble_i[s] = LINK11_SLEW_PREAMBLE_I[s+KNOWN_SEQUENCE_END_SYMBOL+1];
        assign preamble_q[s] = LINK11_SLEW_PREAMBLE_Q[s+KNOWN_SEQUENCE_END_SYMBOL+1];
    end
endgenerate

reg [SYMBOL_INTERVAL_W:0] cnt_symbol;
always @(posedge clk ) begin
    if(~rst_n) begin
        cnt_symbol <= 0;
    end else if(symbol_start) begin
        cnt_symbol <= 0;
    end else begin
        if(symbol_strobe) begin     // 后面的模块freq_est有保护, 可以肆意妄为
            cnt_symbol <= cnt_symbol + 1;
        end
    end
end



// 去掉已知的前导码相位
mixer_strobe #(
    .A_DATA_WIDTH ( SYMBOL_DATA_WIDTH   ),
    .B_DATA_WIDTH ( 16                  ),
    .IMPL_TYPE    ( "DSP"               ),
    .MODE         ( 0                   ))
u_preamble_derotate (
    .clk          ( clk                      ),
    .rst_n        ( rst_n                    ),
    .in_strobe    ( symbol_strobe            ),
    .ai           ( symbol_i                 ),
    .aq           ( symbol_q                 ),
    .bi           ( preamble_i[cnt_symbol]   ),
    .bq           ( preamble_q[cnt_symbol]   ),

    .out_strobe   ( preamble_derot_strobe ),
    .oi           ( preamble_derot_i      ),
    .oq           ( preamble_derot_q      )
);
endmodule