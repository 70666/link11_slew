module link11_slew_step7 #(
    
) (
    input wire clk,
    input wire rst_n,
    input wire device_type,
    input wire [1:0] dibit,
    input wire dibit_strobe,
    input wire equalized_start,         // 每条消息复位step7状态标志
    input wire mixer_mag_envelope,      // 在QPSK判决前的数字信号的每个symbol的包络

// vb译码
    output wire        viterbi_done    ,    
    output wire [59:0] decoded_bits    ,    
    output wire [5:0]  decoded_length  ,    
    output wire [5:0]  best_start_state,    
    output wire [7:0]  best_path_metric,    
// crc check
    output wire        crc_check_pass  ,  
    output wire        crc_check_strobe,
    output reg         demod_done       // 只持续一个时钟
);
    
// 第一步, 解交织
wire deinterleaved_strobe;
wire [89:0] deinterleaved_bits; // 先到来的放在低位, 后到来的在高位
link11_slew_step7_deinterleave  u_link11_slew_step7_deinterleave (
    .clk                     ( clk                          ),
    .rst_n                   ( rst_n                        ),
    .start                   ( equalized_start              ),
    .dibit                   ( dibit                 [1:0]  ),
    .dibit_strobe            ( dibit_strobe                 ),

    .deinterleaved_bits      ( deinterleaved_bits    [89:0] ),
    .deinterleaved_strobe    ( deinterleaved_strobe         )
);

// 第二步, 按照不同的block类型, 进行解卷积编码
// header: 1/2 90bits -> 45bits,    data: 2/3 90bits -> 60bits
// wire [59:0] decoded_bits    ;    
// wire [5:0]  decoded_length  ;    
// wire [5:0]  best_start_state;    
// wire [7:0]  best_path_metric;    
wire        mode_data       ;       // 0: header 1: data
link11_viterbi_decoder  u_link11_viterbi_decoder (
    .clk                     ( clk                              ),
    .rst_n                   ( rst_n                            ),
    .start                   ( deinterleaved_strobe             ),
    .mode_data               ( mode_data                        ),
    .rx_bits                 ( deinterleaved_bits   [89:0]      ),

    .busy                    ( busy                             ),
    .done                    ( viterbi_done                     ),
    .decoded_bits            ( decoded_bits         [59:0]      ),
    .decoded_length          ( decoded_length       [5:0]       ),
    .best_start_state        ( best_start_state     [5:0]       ),
    .best_path_metric        ( best_path_metric     [7:0]       )
);

// 第三步, 按照不同的block, 提取crc, 并验错, 给出是否错误标识
link11_slew_step7_crc_check  u_link11_slew_step7_crc_check (
    .clk                     ( clk                      ),
    .mode_data               ( mode_data                ),
    .viterbi_done            ( viterbi_done             ),
    .decoded_bits            ( decoded_bits      [59:0] ),

    .crc_check_pass          ( crc_check_pass           ),
    .crc_check_strobe        ( crc_check_strobe         )
);


// 第四步, 给出demod_done
link11_slew_step7_flow_ctrl  u_link11_slew_step7_flow_ctrl (
    .clk                     ( clk                          ),
    .rst_n                   ( rst_n                        ),
    .device_type             ( device_type                  ),
    .equalized_start         ( equalized_start              ),
    .deinterleaved_strobe    ( deinterleaved_strobe         ),
    .deinterleaved_bits      ( deinterleaved_bits    [89:0] ),
    .viterbi_done            ( viterbi_done                 ),
    .mixer_mag_envelope      ( mixer_mag_envelope           ),
    .dibit_strobe            ( dibit_strobe                 ),

    .mode_data               ( mode_data                    ),
    .demod_done              ( demod_done                   )
);
endmodule