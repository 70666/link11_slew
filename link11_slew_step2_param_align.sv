module link11_slew_step2_param_align #(
    parameter PROBE_TO_INDEX_LATENCY = 666,
    parameter PROBE_TO_ADDRA_LATENCY = 1,
    parameter ADDRA_WIDTH = 16
) (
    input wire clk,
    input wire [ADDRA_WIDTH-1:0] addra,
    input wire signal_lpf_envelope_strobe,
    input wire envelope,
    output wire [ADDRA_WIDTH-1:0] sum_mag_index,
    output wire sum_mag_probe,
    output wire envelope_sum_mag
);


 

delay #(
    .DATA_WIDTH ( ADDRA_WIDTH ),
    .DELAY_CLK  ( PROBE_TO_INDEX_LATENCY-PROBE_TO_ADDRA_LATENCY ),
    .IMPL_TYPE  ( 0  ))
 u_delay_corr_index (
    .clk                     ( clk          ),
    .data_in                 ( addra        ),

    .data_out                ( sum_mag_index   )
);
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( PROBE_TO_INDEX_LATENCY ),
    .IMPL_TYPE  ( 0  ))
 u_delay_corr_index_probe (
    .clk                     ( clk                  ),
    .data_in                 ( signal_lpf_envelope_strobe    ),

    .data_out                ( sum_mag_probe   )
);
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( PROBE_TO_INDEX_LATENCY ),
    .IMPL_TYPE  ( 0  ))
 u_delay_envelope (
    .clk                     ( clk                  ),
    .data_in                 ( envelope             ),

    .data_out                ( envelope_sum_mag        )
);
endmodule