module link11_slew_step6_sample #(
    parameter WINDOW_NUM = 16,
    parameter EQ_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    input wire [EQ_WIDTH-1:0] equalized_i, equalized_q,   
    input wire equalized_strobe,
    input wire equalized_start,
    input wire demod_done, 
    output reg sample_strobe,
    output reg [EQ_WIDTH-1:0] sample_i, sample_q
);
    
localparam bit IS_POWER2 = (WINDOW_NUM > 0) && ((WINDOW_NUM & (WINDOW_NUM - 1)) == 0);
localparam WINDOW_NUM_POWER2 = IS_POWER2 ? WINDOW_NUM : 2 ** ($clog2(WINDOW_NUM)-1);
localparam SUM_WIDTH = EQ_WIDTH + $clog2(WINDOW_NUM_POWER2);


    reg demoding = 0;
    always @(posedge clk ) begin
        if(~rst_n) begin
            demoding <= 0;
        end else if(demod_done) begin
            demoding <= 0;
        end else if(equalized_start) begin
            demoding <= 1;
        end
    end

reg [$clog2(WINDOW_NUM)-1:0] cnt_window;

reg moving_in_strobe;
reg [EQ_WIDTH-1:0] moving_in_i, moving_in_q;
wire moving_sum_strobe;
wire [SUM_WIDTH-1:0] moving_sum_i, moving_sum_q;

always @(posedge clk ) begin
    if(demoding) begin
        if(equalized_strobe) begin
            if(cnt_window < WINDOW_NUM - 1) begin
                cnt_window <= cnt_window + 1;
            end else begin
                cnt_window <= 0;
            end
            moving_in_strobe <= 1;
            moving_in_i <= equalized_i;
            moving_in_q <= equalized_q;
        end else begin
            moving_in_strobe <= 0;
        end
        if(moving_sum_strobe && cnt_window == WINDOW_NUM_POWER2 - 1) begin
            sample_i <= moving_sum_i[SUM_WIDTH-1-:EQ_WIDTH];
            sample_q <= moving_sum_q[SUM_WIDTH-1-:EQ_WIDTH];
            sample_strobe <= 1;
        end else begin
            sample_strobe <= 0;
        end
    end else begin
        cnt_window <= 0;
        moving_in_strobe <= 0;
        sample_strobe <= 0;
    end
end


moving_sum #(
    .DATA_WIDTH      ( EQ_WIDTH         ),
    .WINDOW_NUM      ( WINDOW_NUM_POWER2),
    .LATENCY         ( 2                ),
    .ARITH_IMPL_TYPE ( "LUT"            ))
 u_moving_sum (
    .clk                     ( clk                           ),
    .rst_n                   ( rst_n                         ),
    .data_in_strobe          ( moving_in_strobe              ),
    .data_in_i               ( moving_in_i                   ),
    .data_in_q               ( moving_in_q                   ),

    .sum_out_i               ( moving_sum_i                 ),
    .sum_out_q               ( moving_sum_q                 ),
    .data_out_strobe         ( moving_sum_strobe            )
);
endmodule