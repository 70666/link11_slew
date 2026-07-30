/*
    将随机初相恢复为正常的前导码初相
*/
module init_phase_correct #(
    parameter SYMBOL_DATA_WIDTH = 16
) (
    input wire clk                                  ,
    input wire rst_n                                ,
    input wire [15:0] first_preamble_standard_i     ,
    input wire [15:0] first_preamble_standard_q     ,
    input wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_i    , 
    input wire [SYMBOL_DATA_WIDTH-1:0] freq_corrected_q    , 
    input wire freq_corrected_strobe                , 
    input wire symbol_start                         ,

    output reg data_for_demod_start                 ,
    output reg data_for_demod_strobe                ,
    output reg [2*SYMBOL_DATA_WIDTH-1:0] data_for_demod_i  , 
    output reg [2*SYMBOL_DATA_WIDTH-1:0] data_for_demod_q  
);



reg first_found;                    // 第一个前导码
reg first_symbol_strobe;            // 对于每个消息, 只会触发一次strobe
reg [SYMBOL_DATA_WIDTH-1:0] first_symbol_in_i, first_symbol_in_q;
always @(posedge clk ) begin
    if(~rst_n) begin
        first_symbol_in_i <= 0;
        first_symbol_in_q <= 0;
        first_symbol_strobe <= 0;
        first_found <= 0;
    end else if(symbol_start) begin
        first_symbol_in_i <= 0;
        first_symbol_in_q <= 0;
        first_symbol_strobe <= 0;
        first_found <= 0;
    end else if(~first_found) begin
        if(freq_corrected_strobe) begin
            first_found <= 1;
            first_symbol_in_i <= freq_corrected_i;
            first_symbol_in_q <= freq_corrected_q;
            first_symbol_strobe <= 1;
        end else begin
            first_symbol_strobe <= 0;
        end
    end else begin
        first_symbol_strobe <= 0;
    end
end

localparam INITIAL_PHASE_WIDTH = SYMBOL_DATA_WIDTH + 15;
wire mixer_out_strobe;
wire [INITIAL_PHASE_WIDTH-1:0] mixer_out_i, mixer_out_q;
// 用前导码的第一个symbol和标准相位模板算出初相
mixer_strobe #(
    .A_DATA_WIDTH ( SYMBOL_DATA_WIDTH ),
    .B_DATA_WIDTH ( 16 ),
    .IMPL_TYPE    ( "DSP"        ),
    .MODE         ( 0         ))
 u_mixer_strobe (
    .clk          ( clk                       ),
    .rst_n        ( rst_n                     ),
    .in_strobe    ( first_symbol_strobe       ),
    .ai           ( first_symbol_in_i         ),
    .aq           ( first_symbol_in_q         ),
    .bi           ( first_preamble_standard_i   ),
    .bq           ( first_preamble_standard_q   ),

    .out_strobe   ( mixer_out_strobe          ),
    .oi           ( mixer_out_i               ),
    .oq           ( mixer_out_q               )
);

// 每次得到新的初相时更新
reg initial_phase_valid;
reg [INITIAL_PHASE_WIDTH-1:0] initial_phase_i, initial_phase_q;
always @(posedge clk ) begin
    if(~rst_n) begin
        initial_phase_valid <= 0;
        initial_phase_i <= 0;
        initial_phase_q <= 0;
    end else if(symbol_start) begin           // 每次解调完成后必须复位
        initial_phase_valid <= 0;
        initial_phase_i <= 0;
        initial_phase_q <= 0;
    end else if(mixer_out_strobe) begin     
        initial_phase_valid <= 1;
        initial_phase_i <= mixer_out_i;
        initial_phase_q <= mixer_out_q;
    end
end

// 从freq_corrected 到 initial_phase共9 clks延时
wire raw_data_strobe; 
wire [SYMBOL_DATA_WIDTH-1:0] raw_data_i, raw_data_q;
delay #(
    .DATA_WIDTH ( 2*SYMBOL_DATA_WIDTH+1 ),
    .DELAY_CLK  ( 9  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_raw_data (
    .clk        ( clk                        ),
    .data_in    ( {freq_corrected_strobe,freq_corrected_q,freq_corrected_i} ),

    .data_out   ( {raw_data_strobe, raw_data_q, raw_data_i} )
);

// 初相校正
localparam INITIAL_PHASE_MIXER_WIDTH = SYMBOL_DATA_WIDTH + INITIAL_PHASE_WIDTH - 1;
wire initial_phase_mixer_out_strobe;
wire [INITIAL_PHASE_MIXER_WIDTH-1:0] initial_phase_mixer_out_i;
wire [INITIAL_PHASE_MIXER_WIDTH-1:0] initial_phase_mixer_out_q;
wire [2*SYMBOL_DATA_WIDTH-1:0] initial_phase_corrected_i, initial_phase_corrected_q;
assign initial_phase_corrected_i = initial_phase_mixer_out_i[INITIAL_PHASE_MIXER_WIDTH-1-:2*SYMBOL_DATA_WIDTH];
assign initial_phase_corrected_q = initial_phase_mixer_out_q[INITIAL_PHASE_MIXER_WIDTH-1-:2*SYMBOL_DATA_WIDTH];
mixer_strobe #(
    .A_DATA_WIDTH ( SYMBOL_DATA_WIDTH   ),
    .B_DATA_WIDTH ( INITIAL_PHASE_WIDTH ),
    .IMPL_TYPE    ( "DSP"               ),
    .MODE         ( 0                   ))
 u_initial_phase_corrected (
    .clk          ( clk                 ),
    .rst_n        ( rst_n               ),
    .in_strobe    ( raw_data_strobe     ),
    .ai           ( raw_data_i          ),
    .aq           ( raw_data_q          ),
    .bi           ( initial_phase_i     ),
    .bq           ( initial_phase_q     ),

    .out_strobe   ( initial_phase_mixer_out_strobe  ),
    .oi           ( initial_phase_mixer_out_i       ),
    .oq           ( initial_phase_mixer_out_q       )
);

always @(posedge clk ) begin
    data_for_demod_start    <= first_symbol_strobe;
    data_for_demod_strobe   <= initial_phase_mixer_out_strobe;
    data_for_demod_i        <= initial_phase_corrected_i;
    data_for_demod_q        <= initial_phase_corrected_q;
end

endmodule