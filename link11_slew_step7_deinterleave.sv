module link11_slew_step7_deinterleave (
    input wire clk,
    input wire rst_n,
    input wire demod_done,                  // 一条消息结束
    input wire start,                       // 每条消息复位step7的解交织状态标志
    input wire [1:0] dibit,                 // qpsk原始2bit, 未加扰
    input wire dibit_strobe,                // dibit有效标志
    output reg [89:0] deinterleaved_bits,   // 解交织bits
    output reg deinterleaved_strobe         // 解交织有效标志
);
    
reg collecting;         // 接收中
    always @(posedge clk ) begin
        if(~rst_n) begin
            collecting <= 0;
        end else if(start) begin
            collecting <= 1;
        end else if(demod_done) begin
            collecting <= 0;
        end
    end

reg [$clog2(64):0] cnt_64;              // 45 symbols + 19 reinsertion probes
reg [89:0] deinterleaved_bits_shift;
reg deinterleaved_shift_strobe;
    always @(posedge clk ) begin
        if(collecting) begin
            if(dibit_strobe) begin
                cnt_64 <= (cnt_64 >= 63)? 0 : (cnt_64 + 1);
                if(cnt_64 <= 44) begin   
                    deinterleaved_bits_shift[cnt_64] <= dibit[1];
                    deinterleaved_bits_shift[45+cnt_64] <= dibit[0];
                    deinterleaved_shift_strobe <= (cnt_64 == 44);
                end else begin
                    deinterleaved_shift_strobe <= 0;
                end
            end else begin
                deinterleaved_shift_strobe <= 0;
            end
        end else begin
            cnt_64 <= 0;
            deinterleaved_shift_strobe <= 0;
        end
    end

    always @(posedge clk ) begin
        deinterleaved_strobe <= deinterleaved_shift_strobe;
        deinterleaved_bits <= deinterleaved_shift_strobe ? deinterleaved_bits_shift : deinterleaved_bits;
    end
endmodule