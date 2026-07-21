module link11_slew_step6_scrambler #(
    parameter KNOWN_SEQUENCE_END_SYMBOL = 5,
    parameter PREAMBLE_SYMBOL_NUM = 192     // 前导码数量
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire strobe,
    input wire demod_done,
    // 相对于strobe有一个延时
    output wire out_strobe,
    output wire [15:0] out_i, out_q
);

// 输出相对于输入strobe的延时
localparam PIPELINE_LATENCY = 1;            // 最小值为1 
    
localparam IDLE = 0;                        // 复位
localparam PREAMBLE_STATE = 1;              // 前导码阶段
localparam DEMOD_STATE = 2;                 // 解码阶段
localparam WAIT_FOR_NEW_STATE = 3;          // 等待下次前导码阶段

reg [1:0] state = IDLE;
reg [$clog2(PREAMBLE_SYMBOL_NUM):0] cnt_preamble;
reg [7:0] cnt;

always @(posedge clk ) begin
    if(~rst_n) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE:               begin
                state <= WAIT_FOR_NEW_STATE;
            end
            PREAMBLE_STATE:     begin
                if(cnt_preamble >= PREAMBLE_SYMBOL_NUM - 1)
                    state <= DEMOD_STATE;
                else
                    state <= PREAMBLE_STATE;
            end
            DEMOD_STATE:        begin
                if(demod_done)
                    state <= WAIT_FOR_NEW_STATE;
                else
                    state <= DEMOD_STATE;
            end
            WAIT_FOR_NEW_STATE: begin
                if(start)
                    state <= PREAMBLE_STATE;
                else
                    state <= WAIT_FOR_NEW_STATE;
            end
        endcase
    end
end

reg data_strobe = 0;
always @(posedge clk ) begin
    case (state)
        IDLE: begin
            cnt_preamble <= KNOWN_SEQUENCE_END_SYMBOL;
            cnt <= 159;
            data_strobe <= 0;
        end
        PREAMBLE_STATE: begin
            cnt <= 159;
            if(strobe)
                cnt_preamble <= cnt_preamble + 1;
            data_strobe <= 0;
        end
        DEMOD_STATE: begin
            cnt_preamble <= KNOWN_SEQUENCE_END_SYMBOL;
            if(strobe) begin
                cnt <= (cnt >= 159)? 0 : (cnt + 1);
            end
            data_strobe <= strobe;
        end
        WAIT_FOR_NEW_STATE: begin
            cnt <= 159;
            cnt_preamble <= KNOWN_SEQUENCE_END_SYMBOL;
            data_strobe <= 0;
        end
    endcase
end


    wire [2:0] scr_sym;

    scrambler_lut  u_scrambler_lut (
        .scr_idx   ( cnt        ),

        .scr_sym   ( scr_sym    )
    );

reg [15:0] scrambler_i, scrambler_q;
    always @(*) begin
        case (scr_sym)
            0: begin    // 0°
                scrambler_i = 16'sd32767;
                scrambler_q = 16'sd0;
            end
            1: begin    // 45°
                scrambler_i = 16'sd23170;
                scrambler_q = 16'sd23170;
            end
            2: begin    // 90°
                scrambler_i = 16'sd0;
                scrambler_q = 16'sd32767;
            end
            3: begin    // 135°
                scrambler_i = -16'sd23170;
                scrambler_q = 16'sd23170;
            end
            4: begin    // 180°
                scrambler_i = -16'sd32767;
                scrambler_q = 16'sd0;
            end
            5: begin    // 225°
                scrambler_i = -16'sd23170;
                scrambler_q = -16'sd23170;
            end
            6: begin    // 270°
                scrambler_i = 16'sd0;
                scrambler_q = -16'sd32767;
            end
            7: begin    // 315°
                scrambler_i = 16'sd23170;
                scrambler_q = -16'sd23170;
            end 
        endcase
    end

delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( PIPELINE_LATENCY - 1  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_strobe (
    .clk                     ( clk          ),
    .data_in                 ( data_strobe  ),

    .data_out                ( out_strobe   )
);    

delay #(
    .DATA_WIDTH ( 32 ),
    .DELAY_CLK  ( PIPELINE_LATENCY - 1  ),
    .IMPL_TYPE  ( 0  ))
 u_delay_data (
    .clk                     ( clk                          ),
    .data_in                 ( {scrambler_q, scrambler_i}   ),

    .data_out                ( {out_q      , out_i      }   )
);   
endmodule