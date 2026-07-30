module link11_slew_step4_data_corrector #(
    parameter LPF_WIDTH = 16,
    parameter WINDOW_NUM = 16,
    parameter PREAMBLE_SYMBOL_NUM = 192,
    parameter CACHE_ADDR_WIDTH = 1
) (
    input wire clk,
    input wire rst_n,
    input wire demod_done,
    input wire [LPF_WIDTH-1:0] data_in_i,
    input wire [LPF_WIDTH-1:0] data_in_q,
    input wire data_in_strobe,
    input wire [LPF_WIDTH-1:0] phase_reference_i,
    input wire [LPF_WIDTH-1:0] phase_reference_q,
    input wire [$clog2(PREAMBLE_SYMBOL_NUM+1)-1:0] preamble_start_symbol_offset,
    input wire phase_reference_valid,
    output wire [LPF_WIDTH-1:0] data_out_i,
    output wire [LPF_WIDTH-1:0] data_out_q,
    output wire data_out_strobe,            // 第一个输出的数据是已知序列最后的下一个symbol
    output reg preamble_aligned_start       // start落后于strobe一个时钟
);


localparam SYMBOL_INDEX_WIDTH = $clog2(PREAMBLE_SYMBOL_NUM + 1);

localparam ADDRESS_LATENCY = 2;
localparam MIXER_OUT_WIDTH = 2 * LPF_WIDTH;
localparam [WINDOW_WIDTH-1:0] WINDOW_NUM_VALUE = WINDOW_NUM;



wire [CACHE_ADDR_WIDTH-1:0] preamble_start_addr;
wire [2*LPF_WIDTH-1:0] phase_reference_delay;
wire phase_reference_valid_delay;



// 相位参考和valid补ADDRESS_LATENCY clks, 与采样地址对齐.
delay #(
    .DATA_WIDTH ( 2 * LPF_WIDTH  ),
    .DELAY_CLK  ( ADDRESS_LATENCY),
    .IMPL_TYPE  ( 0              ))
 u_delay_phase_reference (
    .clk                     ( clk                                      ),
    .data_in                 ( {phase_reference_q, phase_reference_i}   ),

    .data_out                ( phase_reference_delay                    )
);

delay #(
    .DATA_WIDTH ( 1               ),
    .DELAY_CLK  ( ADDRESS_LATENCY ),
    .IMPL_TYPE  ( 0               ))
 u_delay_phase_reference_valid (
    .clk                     ( clk                          ),
    .data_in                 ( phase_reference_valid        ),

    .data_out                ( phase_reference_valid_delay  )
);


reg cache_reading;
wire cache_read_strobe;

// 粗频偏信号缓存RAM读出逻辑
always @(posedge clk) begin
    if(!rst_n) begin
        cache_read_addr <= 0;
        cache_reading <= 0;
    end else if(demod_done) begin
        cache_read_addr <= 0;
        cache_reading <= 0;
    end else if(phase_reference_valid_delay) begin
        cache_read_addr <= preamble_start_addr;
        cache_reading <= 1;
    end else if(cache_read_enable) begin
        if(cache_read_addr == CACHE_DEPTH - 1) begin
            cache_read_addr <= 0;
        end else begin
            cache_read_addr <= cache_read_addr + 1'b1;
        end
    end
end

assign cache_read_enable = cache_reading && data_in_strobe;

// 该延时将读使能对齐到RAM数据, 延时为CACHE_RAM_LATENCY clks.
delay #(
    .DATA_WIDTH ( 1                 ),
    .DELAY_CLK  ( CACHE_RAM_LATENCY ),
    .IMPL_TYPE  ( 0                 ))
 u_delay_cache_read_strobe (
    .clk        ( clk                ),
    .data_in    ( cache_read_enable  ),

    .data_out   ( cache_read_strobe  )
);

wire [MIXER_OUT_WIDTH-1:0] corrected_mixer_i;
wire [MIXER_OUT_WIDTH-1:0] corrected_mixer_q;
wire corrected_mixer_strobe;

// 初相校正混频带来7 clks延时.
mixer_strobe #(
    .A_DATA_WIDTH ( LPF_WIDTH ),
    .B_DATA_WIDTH ( LPF_WIDTH ),
    .IMPL_TYPE    ( "LUT"     ),
    .MODE         ( 0         ))
 u_initial_phase_correction (
    .clk          ( clk                                           ),
    .rst_n        ( rst_n                                         ),
    .in_strobe    ( cache_read_strobe                             ),
    .ai           ( cache_read_data[LPF_WIDTH-1:0]                 ),
    .aq           ( cache_read_data[2*LPF_WIDTH-1:LPF_WIDTH]       ),
    .bi           ( phase_reference_delay[LPF_WIDTH-1:0]           ),
    .bq           ( phase_reference_delay[2*LPF_WIDTH-1:LPF_WIDTH] ),

    .out_strobe   ( corrected_mixer_strobe                        ),
    .oi           ( corrected_mixer_i                             ),
    .oq           ( corrected_mixer_q                             )
);

assign data_out_i = corrected_mixer_i[MIXER_OUT_WIDTH-2-:LPF_WIDTH];
assign data_out_q = corrected_mixer_q[MIXER_OUT_WIDTH-2-:LPF_WIDTH];
assign data_out_strobe = corrected_mixer_strobe;

reg first_output_pending;
always @(posedge clk) begin
    if(!rst_n) begin
        first_output_pending <= 0;
        preamble_aligned_start <= 0;
    end else if(demod_done) begin
        first_output_pending <= 0;
        preamble_aligned_start <= 0;
    end else if(phase_reference_valid_delay) begin
        first_output_pending <= 1;
        preamble_aligned_start <= 0;
    end else if(corrected_mixer_strobe && first_output_pending) begin
        first_output_pending <= 0;
        preamble_aligned_start <= 1;
    end else begin
        preamble_aligned_start <= 0;
    end
end

endmodule
