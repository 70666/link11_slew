// 延时signal_in指定个strobe延时的同时会有一个额外的clk延时
module strobe_delay #
(
    parameter integer DELAY_W   = 16,
    parameter integer DATA_W    = 16,
    parameter integer MAX_DELAY = 32   // delay最大支持值（按有效strobe个数计）
)
(
    input  wire                    clk,
    input  wire                    rstn,

    input  wire [DATA_W-1:0]       signal_in,
    input  wire                    strobe_in,
    input  wire [DELAY_W-1:0]      delay,

    output reg  [DATA_W-1:0]       signal_out,
    output reg                     strobe_out
);

    localparam integer DEPTH   = (MAX_DELAY < 1) ? 1 : MAX_DELAY;
    localparam integer PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    // 让delay端口支持 0 ~ MAX_DELAY
    // localparam integer DELAY_W = (MAX_DELAY <= 1) ? 1 : $clog2(MAX_DELAY + 1);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0]  wr_ptr;
    reg [COUNT_W-1:0] valid_count; // 当前已经缓存了多少个“有效strobe数据”

    integer i;

    // 计算：当前wr_ptr往前数 delay 个有效样本，对应的地址
    function [PTR_W-1:0] calc_rd_idx;
        input [PTR_W-1:0] cur_wr_ptr;
        input [DELAY_W-1:0] cur_delay;
        integer tmp;
        begin
            tmp = cur_wr_ptr - cur_delay;
            if (tmp < 0)
                tmp = tmp + DEPTH;
            calc_rd_idx = tmp[PTR_W-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            wr_ptr      <= {PTR_W{1'b0}};
            valid_count <= {COUNT_W{1'b0}};
            signal_out  <= {DATA_W{1'b0}};
            strobe_out  <= 1'b0;

            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_W{1'b0}};
            end
        end
        else begin
            // 默认无输出strobe
            strobe_out <= 1'b0;

            if (strobe_in) begin
                // delay=0：当前有效数据直接输出，同拍
                if (delay == 0) begin
                    signal_out <= signal_in;
                    strobe_out <= 1'b1;
                end
                // delay超出MAX_DELAY：这里直接不给有效输出
                else if (delay > MAX_DELAY) begin
                    strobe_out <= 1'b0;
                end
                // 历史有效样本足够：输出 delay 个有效strobe之前的数据
                else if (valid_count >= delay) begin
                    signal_out <= mem[calc_rd_idx(wr_ptr, delay)];
                    strobe_out <= 1'b1;
                end
                // else: 历史数据还不够，strobe_out保持0

                // 无论当前能不能输出，只要strobe_in有效，就把当前输入记入缓冲
                mem[wr_ptr] <= signal_in;

                // 写指针循环前进
                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= {PTR_W{1'b0}};
                else
                    wr_ptr <= wr_ptr + 1'b1;

                // 有效缓存计数饱和到DEPTH
                if (valid_count < DEPTH)
                    valid_count <= valid_count + 1'b1;
            end
        end
    end

endmodule