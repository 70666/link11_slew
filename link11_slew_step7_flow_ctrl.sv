module link11_slew_step7_flow_ctrl (
    input wire clk,
    input wire rst_n,
    input wire device_type,                 // picket / ncs
    input wire equalized_start,             // 每个link11消息开始标志
    input wire deinterleaved_strobe,        // 解交织有效标志
    input wire [89:0] deinterleaved_bits,   
    input wire viterbi_done,
    input wire mixer_mag_envelope,          // 解QPSK前的每个symbol对应包络结果
    input wire dibit_strobe,
    output reg mode_data,                   // 0: header 1: data
    output reg demod_done
);

localparam NCS = 0;
localparam PICKET = 1;
localparam EOM_TOLERANCE_THRESHOLD = 86;

wire [6:0] ones_count;
reg [6:0] ones_count_pipe;
reg deinterleaved_strobe_pipe;
always @(posedge clk ) begin
    if(~rst_n) begin
        ones_count_pipe <= 0;
        deinterleaved_strobe_pipe <= 0;
    end else begin
        ones_count_pipe <= ones_count;
        deinterleaved_strobe_pipe <= deinterleaved_strobe;
    end
end
assign ones_count = $countones(deinterleaved_bits);


// 包络计数, 在没有EOM段的时候, 用来给demod_done保底
reg [2:0] cnt_envelope_low = 0;
reg demoding = 0;
always @(posedge clk ) begin
    if(equalized_start) begin
        cnt_envelope_low <= 0;
    end else if(dibit_strobe) begin
        if(~mixer_mag_envelope)
            cnt_envelope_low <= (cnt_envelope_low >= 7)? cnt_envelope_low : cnt_envelope_low + 1;
        else
            cnt_envelope_low <= 0;
    end
    if(equalized_start) begin
        demoding <= 1;
    end else if(demod_done) begin
        demoding <= 0;
    end
end

// 包络连低4个symbol, 解到EOM字段, 或者header 的T为1, 没有EOM字段
wire eom_block_found;
assign eom_block_found = (cnt_envelope_low >= 4) || deinterleaved_strobe_pipe && 
(
    ones_count_pipe <= (90 - EOM_TOLERANCE_THRESHOLD) && device_type == NCS || 
    ones_count_pipe >= EOM_TOLERANCE_THRESHOLD      && device_type == PICKET
);

always @(posedge clk ) begin
    if(~rst_n) begin
        demod_done <= 0;
    end else if(eom_block_found && demoding) begin   // 确保复位不会太频繁
        demod_done <= 1;
    end else begin
        demod_done <= 0;
    end
end

always @(posedge clk ) begin
    if(~rst_n) begin
        mode_data <= 0;
    end else if(equalized_start) begin  // 开始第一帧
        mode_data <= 0;
    end else if(viterbi_done) begin     // 数据区
        mode_data <= 1;
    end
end
endmodule