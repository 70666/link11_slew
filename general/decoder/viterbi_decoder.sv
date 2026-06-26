`timescale 1ns / 1ps

// 硬判决 Viterbi 译码器。
// 默认用于码率 1/2、约束长度 K=7、生成多项式 171/133(octal) 的卷积码。
//
// 如果只从卷积编码的正向过程理解:
// 1. 编码器每输入 1 bit, 移位寄存器就向前移动一次。
// 2. K=7 时, 当前输入 bit 加上之前保存的 6 bit, 一共 7 bit 参与异或生成 2 bit 输出。
// 3. 编码器真正的状态不是全部 7 bit, 而是"之前保存的 6 bit", 所以状态数为 2^6=64。
// 4. 如果已知上一拍状态和本拍输入 bit, 就能算出本拍应该输出哪 2 bit。
//
// Viterbi 译码就是把上面的过程反过来想:
// 1. 接收端每收到 2 bit, 并不知道发送端这一拍输入的是 0 还是 1。
// 2. 对每一个可能的当前状态, 倒推会发现它只可能来自两个上一拍状态:
//    一个对应上一拍移位寄存器最低位为 0, 一个对应最低位为 1。
// 3. 这两条进入当前状态的路径, 各自都能正向算出"理论应该收到的 2 bit"。
// 4. 理论 2 bit 和真实 rx_bits 不一样的个数叫分支度量, 硬判决下只能是 0、1、2。
// 5. 上一拍累积误差加上本拍分支度量, 得到这一条候选路径的新累积误差。
// 6. 对同一个当前状态, 只保留累积误差更小的那条路径, 这条路径叫幸存路径。
// 7. 每拍都保存"每个当前状态选择了哪条进入路径", 保存足够多拍后再回溯,
//    就能得到较早以前最可信的输入 bit。
//
// 本模块采用硬判决输入, rx_bits 已经是 0/1 判决结果, 不包含软信息置信度。
// 若后续需要软判决 Viterbi, 分支度量部分需要改成距离计算, 其余幸存路径思想相同。
//
// 端口约定:
// 1. rx_bits[1] 对应 POLY_0 编码输出, rx_bits[0] 对应 POLY_1 编码输出。
// 2. in_ready 为 1 时才接收 in_strobe, 上游需要用 in_ready 控制送数。
// 3. out_strobe 拉高时 decoded_bit 有效。
//
// 延时说明:
// 1. 接收 1 个码字后, 内部路径度量更新延时为
//    ADD_LATENCY + 1 + SUB_LATENCY 个 fabric clk。
// 2. out_strobe 相对已经接收的码字流约延时 TRACEBACK_DEPTH 个有效码字。
// 3. 本模块例化的 Adder/Subtracter 属于延时敏感模块, 对应延时见例化上方注释。
module viterbi_decoder #(
    parameter integer CONSTRAINT_LEN   = 7,
    parameter [CONSTRAINT_LEN-1:0] POLY_0 = 7'o171,
    parameter [CONSTRAINT_LEN-1:0] POLY_1 = 7'o133,
    parameter integer TRACEBACK_DEPTH  = 36,
    parameter integer METRIC_WIDTH     = 12,
    parameter integer ADD_LATENCY      = 2,
    parameter integer SUB_LATENCY      = 2
) (
    input  wire clk,
    input  wire rst_n,
    input  wire in_strobe,
    input  wire [1:0] rx_bits,

    output wire in_ready,
    output reg  out_strobe,
    output reg  decoded_bit,
    output reg  [CONSTRAINT_LEN-2:0] debug_best_state,
    output reg  [METRIC_WIDTH-1:0] debug_best_metric
);

    localparam ARITH_IMPL_TYPE = "LUT";

    localparam integer STATE_BITS       = CONSTRAINT_LEN - 1;
    localparam integer STATE_NUM        = 1 << STATE_BITS;
    localparam integer TB_ADDR_WIDTH    = (TRACEBACK_DEPTH <= 2) ? 1 : $clog2(TRACEBACK_DEPTH);
    localparam integer COUNT_WIDTH      = (TRACEBACK_DEPTH <= 1) ? 1 : $clog2(TRACEBACK_DEPTH + 1);
    localparam integer UPDATE_LATENCY   = ADD_LATENCY + 1 + SUB_LATENCY;
    localparam integer BUSY_WIDTH       = (UPDATE_LATENCY <= 1) ? 1 : $clog2(UPDATE_LATENCY + 1);
    localparam integer DECISION_DELAY   = SUB_LATENCY + 1;

    // INVALID_METRIC 不取全 1, 避免加上分支度量时回绕。
    localparam [METRIC_WIDTH-1:0] INVALID_METRIC = {
        1'b0,
        1'b1,
        {(METRIC_WIDTH-2){1'b0}}
    };
    localparam [TB_ADDR_WIDTH-1:0] LAST_TB_ADDR = TRACEBACK_DEPTH - 1;
    localparam [COUNT_WIDTH-1:0] TB_DEPTH_COUNT = TRACEBACK_DEPTH;
    localparam [BUSY_WIDTH-1:0] UPDATE_LATENCY_COUNT = UPDATE_LATENCY;

    initial begin
        if (CONSTRAINT_LEN < 2) begin
            $error("viterbi_decoder: CONSTRAINT_LEN must be greater than 1.");
        end
        if (TRACEBACK_DEPTH < 1) begin
            $error("viterbi_decoder: TRACEBACK_DEPTH must be greater than 0.");
        end
        if (METRIC_WIDTH < 4) begin
            $error("viterbi_decoder: METRIC_WIDTH must be greater than 3.");
        end
        if ((ADD_LATENCY < 2) || (SUB_LATENCY < 2)) begin
            $error("viterbi_decoder: ADD_LATENCY and SUB_LATENCY must be greater than 1.");
        end
    end

    // path_metric[state] 表示"走到该状态时, 到目前为止累计不匹配的数量"。
    // 度量越小, 说明这条路径越像真实发送路径。
    reg [METRIC_WIDTH-1:0] path_metric [0:STATE_NUM-1];

    // selected_metric[state] 保存本拍 ACS 选择后的度量。
    // 它先进入 Subtracter 做归一化, 再写回 path_metric。
    reg [METRIC_WIDTH-1:0] selected_metric [0:STATE_NUM-1];

    // survivor_mem[time][state] 保存某个时间点、某个当前状态选择的上一拍分支。
    // 0 表示选择 prev_state_0, 1 表示选择 prev_state_1。
    // 回溯时沿着这些 0/1 分支往前走, 就能找到历史输入 bit。
    reg [STATE_NUM-1:0] survivor_mem [0:TRACEBACK_DEPTH-1];

    // decision_pipe 用来把幸存分支选择结果对齐到归一化后的 path_metric 更新时刻。
    // 因为 selected_metric 经过 Subtracter 后才写回, 幸存分支也必须延时相同拍数。
    reg [STATE_NUM-1:0] decision_pipe [0:DECISION_DELAY-1];
    reg [TB_ADDR_WIDTH-1:0] wr_addr;
    reg [COUNT_WIDTH-1:0] valid_count;
    reg [BUSY_WIDTH-1:0] busy_count;
    reg [ADD_LATENCY-1:0] add_valid_pipe;
    reg [DECISION_DELAY-1:0] update_valid_pipe;

    wire accept_strobe;
    wire add_valid;
    wire update_valid;
    wire [1:0] branch_metric_0 [0:STATE_NUM-1];
    wire [1:0] branch_metric_1 [0:STATE_NUM-1];
    wire [METRIC_WIDTH-1:0] metric_add_0 [0:STATE_NUM-1];
    wire [METRIC_WIDTH-1:0] metric_add_1 [0:STATE_NUM-1];
    wire [METRIC_WIDTH-1:0] metric_next [0:STATE_NUM-1];
    wire [METRIC_WIDTH-1:0] selected_metric_w [0:STATE_NUM-1];
    wire [STATE_NUM-1:0] decision_w;
    wire [METRIC_WIDTH-1:0] selected_best_metric_w;
    wire [STATE_BITS-1:0] selected_best_state_w;
    wire [STATE_BITS-1:0] path_best_state_w;
    wire traceback_bit_w;

    integer state_idx;
    integer metric_idx;
    integer mem_idx;
    integer pipe_idx;

    assign in_ready = (busy_count == {BUSY_WIDTH{1'b0}});
    assign accept_strobe = in_strobe & in_ready;
    assign add_valid = add_valid_pipe[ADD_LATENCY-1];
    assign update_valid = update_valid_pipe[DECISION_DELAY-1];

    // 按卷积编码器的正向逻辑计算理论输出。
    // prev_state 是上一拍寄存器中保存的 K-1 个历史 bit。
    // in_bit 是假设本拍输入的 bit。
    // shift_data = {in_bit, prev_state} 就是编码器这一拍参与多项式异或的 K bit。
    function automatic [1:0] branch_bits;
        input [STATE_BITS-1:0] prev_state;
        input in_bit;
        reg [CONSTRAINT_LEN-1:0] shift_data;
        begin
            shift_data = {in_bit, prev_state};
            branch_bits[1] = ^(shift_data & POLY_0);
            branch_bits[0] = ^(shift_data & POLY_1);
        end
    endfunction

    // 硬判决分支度量。
    // expect_bits 是某条候选路径理论应该输出的 2 bit。
    // receive_bits 是实际收到的 2 bit。
    // 二者不同的 bit 数越少, 说明该候选路径越可信。
    function automatic [1:0] hamming2;
        input [1:0] expect_bits;
        input [1:0] receive_bits;
        reg [1:0] diff_bits;
        begin
            diff_bits = expect_bits ^ receive_bits;
            case (diff_bits)
                2'b00: hamming2 = 2'd0;
                2'b01: hamming2 = 2'd1;
                2'b10: hamming2 = 2'd1;
                default: hamming2 = 2'd2;
            endcase
        end
    endfunction

    genvar gen_state;
    generate
        for (gen_state = 0; gen_state < STATE_NUM; gen_state = gen_state + 1) begin : gen_acs_math
            localparam integer NEXT_STATE_I = gen_state;
            localparam integer LOW_MASK_I = (1 << (STATE_BITS - 1)) - 1;
            localparam integer PREV_STATE_0_I = (NEXT_STATE_I & LOW_MASK_I) << 1;
            localparam integer PREV_STATE_1_I = PREV_STATE_0_I | 1;
            localparam [STATE_BITS-1:0] NEXT_STATE = NEXT_STATE_I[STATE_BITS-1:0];
            localparam [STATE_BITS-1:0] PREV_STATE_0 = PREV_STATE_0_I[STATE_BITS-1:0];
            localparam [STATE_BITS-1:0] PREV_STATE_1 = PREV_STATE_1_I[STATE_BITS-1:0];

            // 对一个固定的当前状态 NEXT_STATE 来说, 它只可能由两个上一拍状态转移而来。
            // 原因来自卷积编码器移位关系:
            // 当前状态 = {本拍输入 bit, 上一拍状态的高 STATE_BITS-1 位}
            // 所以上一拍状态的最低位已经被移出, 它可能是 0, 也可能是 1。
            // 这两个可能的上一拍状态就是 PREV_STATE_0 和 PREV_STATE_1。
            assign branch_metric_0[gen_state] =
                hamming2(branch_bits(PREV_STATE_0, NEXT_STATE[STATE_BITS-1]), rx_bits);
            assign branch_metric_1[gen_state] =
                hamming2(branch_bits(PREV_STATE_1, NEXT_STATE[STATE_BITS-1]), rx_bits);

            // ACS 中的 Compare 和 Select:
            // 两条路径都能到达同一个当前状态, 只保留累计误差更小的一条。
            // decision_w[state]=0 表示保留 PREV_STATE_0 这条路径。
            // decision_w[state]=1 表示保留 PREV_STATE_1 这条路径。
            assign decision_w[gen_state] = (metric_add_1[gen_state] < metric_add_0[gen_state]);
            assign selected_metric_w[gen_state] = decision_w[gen_state] ?
                metric_add_1[gen_state] : metric_add_0[gen_state];

            // 该 Adder 带来 ADD_LATENCY 个 fabric clk 延时。
            // 计算 prev_state_0 路径的新累计误差:
            // 新累计误差 = 上一拍走到 prev_state_0 的累计误差 + 本拍分支度量。
            Adder #(
                .IMPL_TYPE ( ARITH_IMPL_TYPE ),
                .A_WIDTH   ( METRIC_WIDTH    ),
                .B_WIDTH   ( 2               ),
                .A_TYPE    ( 0               ),
                .B_TYPE    ( 0               ),
                .OUT_WIDTH ( METRIC_WIDTH    ),
                .LATENCY   ( ADD_LATENCY     ))
            u_add_metric_0 (
                .clk ( clk                         ),
                .A   ( path_metric[PREV_STATE_0_I] ),
                .B   ( branch_metric_0[gen_state]  ),
                .SUM ( metric_add_0[gen_state]     )
            );

            // 该 Adder 带来 ADD_LATENCY 个 fabric clk 延时。
            // 计算 prev_state_1 路径的新累计误差:
            // 新累计误差 = 上一拍走到 prev_state_1 的累计误差 + 本拍分支度量。
            Adder #(
                .IMPL_TYPE ( ARITH_IMPL_TYPE ),
                .A_WIDTH   ( METRIC_WIDTH    ),
                .B_WIDTH   ( 2               ),
                .A_TYPE    ( 0               ),
                .B_TYPE    ( 0               ),
                .OUT_WIDTH ( METRIC_WIDTH    ),
                .LATENCY   ( ADD_LATENCY     ))
            u_add_metric_1 (
                .clk ( clk                         ),
                .A   ( path_metric[PREV_STATE_1_I] ),
                .B   ( branch_metric_1[gen_state]  ),
                .SUM ( metric_add_1[gen_state]     )
            );

            // 该 Subtracter 带来 SUB_LATENCY 个 fabric clk 延时。
            // 对路径度量做归一化:
            // 所有状态度量同时减去本拍最小度量, 最优路径度量变成 0。
            // 这样长时间连续译码时度量不会一直增加导致溢出。
            // 各路径之间的相对大小不变, 所以不会影响 Viterbi 判决结果。
            Subtracter #(
                .IMPL_TYPE ( ARITH_IMPL_TYPE ),
                .A_WIDTH   ( METRIC_WIDTH    ),
                .B_WIDTH   ( METRIC_WIDTH    ),
                .A_TYPE    ( 0               ),
                .B_TYPE    ( 0               ),
                .OUT_WIDTH ( METRIC_WIDTH    ),
                .LATENCY   ( SUB_LATENCY     ))
            u_sub_best_metric (
                .clk ( clk                        ),
                .A   ( selected_metric[gen_state] ),
                .B   ( debug_best_metric          ),
                .SUM ( metric_next[gen_state]     )
            );
        end
    endgenerate

    // 组合比较模块, 计算本次 ACS 后的最优状态和最小度量。
    // 该最小度量用于归一化, selected_best_state_w 仅用于调试观察。
    // 时序逻辑只采样该模块输出, 不在 posedge 块里做比较树。
    viterbi_best_state #(
        .STATE_BITS   ( STATE_BITS   ),
        .METRIC_WIDTH ( METRIC_WIDTH ))
    u_selected_best_state (
        .metric_in   ( selected_metric_w      ),
        .best_metric ( selected_best_metric_w ),
        .best_state  ( selected_best_state_w  )
    );

    // 组合比较模块, 计算当前 path_metric 中最可信的状态。
    // 回溯需要一个起点, 通常从当前累计误差最小的状态开始往前找。
    viterbi_best_state #(
        .STATE_BITS   ( STATE_BITS   ),
        .METRIC_WIDTH ( METRIC_WIDTH ))
    u_path_best_state (
        .metric_in   ( path_metric        ),
        .best_metric (                  ),
        .best_state  ( path_best_state_w  )
    );

    // 组合回溯模块, 根据已经写入的幸存路径给出当前可判决比特。
    // 直观理解:
    // 1. 当前最优状态可能还会受最近几拍噪声影响。
    // 2. 往前回溯 TRACEBACK_DEPTH 拍后, 各条可能路径通常已经合并到同一条可信路径。
    // 3. 此时回溯到的状态最高位, 就是较早那一拍输入进编码器的 bit。
    viterbi_traceback #(
        .STATE_BITS      ( STATE_BITS      ),
        .TRACEBACK_DEPTH ( TRACEBACK_DEPTH ))
    u_traceback (
        .survivor_mem  ( survivor_mem     ),
        .wr_addr       ( wr_addr          ),
        .start_state   ( path_best_state_w ),
        .decoded_bit   ( traceback_bit_w  )
    );

    // 接收一个码字后, 要等待内部 Adder、选择寄存、Subtracter 流水线结束。
    // busy_count 非 0 时 in_ready 为 0, 上游不能再送新的 rx_bits。
    // 这样可以保证 path_metric 先完成更新, 再处理下一个码字。
    always @(posedge clk) begin
        if (!rst_n) begin
            busy_count <= {BUSY_WIDTH{1'b0}};
        end else if (accept_strobe) begin
            busy_count <= UPDATE_LATENCY_COUNT;
        end else if (busy_count != {BUSY_WIDTH{1'b0}}) begin
            busy_count <= busy_count - 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            add_valid_pipe <= {ADD_LATENCY{1'b0}};
            update_valid_pipe <= {DECISION_DELAY{1'b0}};
        end else begin
            add_valid_pipe <= {add_valid_pipe[ADD_LATENCY-2:0], accept_strobe};
            update_valid_pipe <= {update_valid_pipe[DECISION_DELAY-2:0], add_valid};
        end
    end

    // 采样 ACS 组合结果。
    // selected_metric 保存每个当前状态被选中的累计误差。
    // decision_pipe[0] 保存每个当前状态选择了哪条上一拍分支。
    // 注意: 比较和选择已经在时序块外完成, 这里仅寄存结果。
    always @(posedge clk) begin
        if (!rst_n) begin
            for (state_idx = 0; state_idx < STATE_NUM; state_idx = state_idx + 1) begin
                selected_metric[state_idx] <= {METRIC_WIDTH{1'b0}};
            end
            decision_pipe[0] <= {STATE_NUM{1'b0}};
            debug_best_metric <= {METRIC_WIDTH{1'b0}};
            debug_best_state <= {STATE_BITS{1'b0}};
        end else if (add_valid) begin
            for (state_idx = 0; state_idx < STATE_NUM; state_idx = state_idx + 1) begin
                selected_metric[state_idx] <= selected_metric_w[state_idx];
            end

            decision_pipe[0] <= decision_w;
            debug_best_metric <= selected_best_metric_w;
            debug_best_state <= selected_best_state_w;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            for (pipe_idx = 1; pipe_idx < DECISION_DELAY; pipe_idx = pipe_idx + 1) begin
                decision_pipe[pipe_idx] <= {STATE_NUM{1'b0}};
            end
        end else begin
            for (pipe_idx = 1; pipe_idx < DECISION_DELAY; pipe_idx = pipe_idx + 1) begin
                decision_pipe[pipe_idx] <= decision_pipe[pipe_idx-1];
            end
        end
    end

    // 更新路径度量和幸存路径。
    // metric_next 已经是归一化后的路径度量, 写回 path_metric 后供下一码字使用。
    // survivor_mem 写入与 metric_next 对齐后的幸存分支。
    // valid_count 统计已经接收并更新了多少个码字, 回溯深度足够后才输出 decoded_bit。
    always @(posedge clk) begin
        if (!rst_n) begin
            for (metric_idx = 0; metric_idx < STATE_NUM; metric_idx = metric_idx + 1) begin
                if (metric_idx == 0) begin
                    path_metric[metric_idx] <= {METRIC_WIDTH{1'b0}};
                end else begin
                    path_metric[metric_idx] <= INVALID_METRIC;
                end
            end

            for (mem_idx = 0; mem_idx < TRACEBACK_DEPTH; mem_idx = mem_idx + 1) begin
                survivor_mem[mem_idx] <= {STATE_NUM{1'b0}};
            end

            wr_addr <= {TB_ADDR_WIDTH{1'b0}};
            valid_count <= {COUNT_WIDTH{1'b0}};
            out_strobe <= 1'b0;
            decoded_bit <= 1'b0;
        end else if (update_valid) begin
            for (metric_idx = 0; metric_idx < STATE_NUM; metric_idx = metric_idx + 1) begin
                path_metric[metric_idx] <= metric_next[metric_idx];
            end
            survivor_mem[wr_addr] <= decision_pipe[DECISION_DELAY-1];

            if (wr_addr == LAST_TB_ADDR) begin
                wr_addr <= {TB_ADDR_WIDTH{1'b0}};
            end else begin
                wr_addr <= wr_addr + 1'b1;
            end

            if (valid_count < TB_DEPTH_COUNT) begin
                valid_count <= valid_count + 1'b1;
            end

            if (valid_count == TB_DEPTH_COUNT) begin
                out_strobe <= 1'b1;
                decoded_bit <= traceback_bit_w;
            end else begin
                out_strobe <= 1'b0;
                decoded_bit <= 1'b0;
            end
        end else begin
            out_strobe <= 1'b0;
        end
    end

endmodule


// 组合最优状态选择。
//
// 输入是一组路径度量 metric_in[state]。
// metric_in[state] 越小, 表示"走到 state 这条路径"和接收码字越接近。
//
// 本模块有两个用途:
// 1. 在 ACS 后找本拍最小度量, 供归一化使用。
// 2. 在回溯前找当前最可信状态, 作为回溯起点。
//
// 放在时序逻辑外, 让 always @(posedge clk) 只负责采样 best_* 结果。
module viterbi_best_state #(
    parameter integer STATE_BITS = 6,
    parameter integer METRIC_WIDTH = 12
) (
    input  wire [METRIC_WIDTH-1:0] metric_in [0:(1 << STATE_BITS)-1],
    output reg  [METRIC_WIDTH-1:0] best_metric,
    output reg  [STATE_BITS-1:0] best_state
);

    localparam integer STATE_NUM = 1 << STATE_BITS;

    integer state_idx;

    always @(*) begin
        best_metric = metric_in[0];
        best_state = {STATE_BITS{1'b0}};
        for (state_idx = 1; state_idx < STATE_NUM; state_idx = state_idx + 1) begin
            if (metric_in[state_idx] < best_metric) begin
                best_metric = metric_in[state_idx];
                best_state = state_idx[STATE_BITS-1:0];
            end
        end
    end

endmodule


// 组合幸存路径回溯。
//
// survivor_mem 保存的是每个时间点、每个状态选择了哪条上一拍分支。
// 对某个当前状态来说:
// decision=0 表示上一拍状态最低位为 0;
// decision=1 表示上一拍状态最低位为 1。
//
// 为什么可以这样回溯:
// 卷积编码器正向移位时:
// 当前状态 = {本拍输入 bit, 上一拍状态[STATE_BITS-1:1]}
// 所以反向回溯时:
// 上一拍状态 = {当前状态[STATE_BITS-2:0], decision}
//
// 回溯 TRACEBACK_DEPTH 拍后, trace_state 的最高位就是那一拍输入编码器的 bit。
// 这个 bit 已经离当前时刻足够远, 一般路径已经收敛, 判决更可靠。
//
// 放在时序逻辑外, 避免在 always @(posedge clk) 中执行回溯计算。
module viterbi_traceback #(
    parameter integer STATE_BITS = 6,
    parameter integer TRACEBACK_DEPTH = 36
) (
    input  wire [(1 << STATE_BITS)-1:0] survivor_mem [0:TRACEBACK_DEPTH-1],
    input  wire [((TRACEBACK_DEPTH <= 2) ? 1 : $clog2(TRACEBACK_DEPTH))-1:0] wr_addr,
    input  wire [STATE_BITS-1:0] start_state,
    output reg  decoded_bit
);

    localparam integer TB_ADDR_WIDTH = (TRACEBACK_DEPTH <= 2) ? 1 : $clog2(TRACEBACK_DEPTH);

    reg [STATE_BITS-1:0] trace_state;
    integer trace_idx;

    function automatic [TB_ADDR_WIDTH-1:0] traceback_addr;
        input [TB_ADDR_WIDTH-1:0] base_addr;
        input integer back_num;
        integer addr_tmp;
        begin
            addr_tmp = base_addr + TRACEBACK_DEPTH - back_num;
            if (addr_tmp >= TRACEBACK_DEPTH) begin
                addr_tmp = addr_tmp - TRACEBACK_DEPTH;
            end
            traceback_addr = addr_tmp[TB_ADDR_WIDTH-1:0];
        end
    endfunction

    always @(*) begin
        trace_state = start_state;
        for (trace_idx = 1; trace_idx < TRACEBACK_DEPTH; trace_idx = trace_idx + 1) begin
            trace_state = {
                trace_state[STATE_BITS-2:0],
                survivor_mem[traceback_addr(wr_addr, trace_idx)][trace_state]
            };
        end
        decoded_bit = trace_state[STATE_BITS-1];
    end

endmodule
