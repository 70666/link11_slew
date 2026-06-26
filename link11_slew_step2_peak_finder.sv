module link11_slew_step2_peak_finder #(
    parameter WINDOW_NUM = 16,
    parameter ADDRA_WIDTH = 16,
    parameter SUM_WIDTH = 18,
    parameter RAM_LATENCY = 1,
    parameter DATA_WIDTH = 16,
    parameter SEARCH_LENGTH = 16,
    parameter WRITE_DEPTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire envelope_sum_mag,
    input wire demod_done,
    input wire sum_mag_probe,
    input wire [SUM_WIDTH-1:0] sum_mag,
    input wire [ADDRA_WIDTH-1:0] sum_mag_index,
    input wire [2*DATA_WIDTH-1:0] doutb,
    output reg enb,
    output reg [ADDRA_WIDTH-1:0] addrb,
    output reg signal_valid_start,
    output wire symbol_aligned_strobe,
    output wire [DATA_WIDTH-1:0] symbol_aligned_i, symbol_aligned_q
);
    
localparam IDLE = 0;
localparam SEARCHING_PEAK = 1;
localparam DEMODING = 2;

reg [1:0] state = 0;
reg [$clog2(SEARCH_LENGTH):0] cnt_searching;
reg [ADDRA_WIDTH-1:0] start_addr;
reg [SUM_WIDTH-1:0] mag_peak;

always @(posedge clk ) begin
    if(~rst_n) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE: 
                begin
                    if(envelope_sum_mag)
                        state <= SEARCHING_PEAK;
                    else
                        state <= IDLE;
                end
            SEARCHING_PEAK:
                begin
                    if(cnt_searching == SEARCH_LENGTH) 
                        state <= DEMODING;
                    else if(~envelope_sum_mag) 
                        state <= IDLE;
                    else
                        state <= SEARCHING_PEAK;
                end
            DEMODING:
                begin
                    if(demod_done)
                        state <= IDLE;
                    else
                        state <= DEMODING;
                end
        endcase
    end
end
always @(posedge clk ) begin
    case (state)
        IDLE: begin
            cnt_searching <= 0;
            start_addr <= 0;
            mag_peak <= 0;
            enb <= 0;
            signal_valid_start <= 0;
        end
        SEARCHING_PEAK: begin
            if(sum_mag_probe) begin
                cnt_searching <= cnt_searching + 1;
            end else begin
                cnt_searching <= cnt_searching;
            end
            if(sum_mag_probe) begin
                if(mag_peak < sum_mag) begin
                    mag_peak <= sum_mag;
                    start_addr <= sum_mag_index;
                end
            end
            if(cnt_searching == SEARCH_LENGTH) begin
                signal_valid_start <= 1;
                addrb <= start_addr;
            end else begin
                signal_valid_start <= 0;
                addrb <= 0;
            end
        end
        DEMODING: begin
            signal_valid_start <= 0;
            if(sum_mag_probe) begin
                enb <= 1;   
                addrb <= (addrb == WRITE_DEPTH - 1)? 0 : addrb + 1;   // 跳过起始, 起始是峰值最高, 但不是解调开始  
            end else begin
                enb <= 0;
                addrb <= addrb;
            end 
        end 
    endcase
end

delay #(
    .DATA_WIDTH ( 1             ),
    .DELAY_CLK  ( RAM_LATENCY   ),
    .IMPL_TYPE  ( 0             ))
 u_delay_demod_data_strobe (
    .clk                     ( clk                  ),
    .data_in                 ( enb    ),

    .data_out                ( symbol_aligned_strobe   )
);

assign symbol_aligned_i = doutb[DATA_WIDTH-1:0];
assign symbol_aligned_q = doutb[2*DATA_WIDTH-1:DATA_WIDTH];
endmodule