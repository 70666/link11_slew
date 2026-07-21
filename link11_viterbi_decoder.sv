`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Link-11 SLEW hard-decision FTBCB Viterbi decoder
//
// STANAG 5511 Annex B, Figure B-17 / para. 11.1.1.2:
//   Header : K=7, rate 1/2, generators (133,171)_oct, 45 input bits
//   CDS data: K=7 mother code, generators (163,135)_oct, punctured to 2/3,
//             60 input bits.  The transmitted pattern for every two input
//             bits is T1,T2,T1; the second T2 is an erasure.
//
// This module performs exact maximum-likelihood tail-biting decoding by trying
// all 64 possible initial states.  For each trial, the final state is forced to
// equal that initial state, and the minimum-metric closed path is selected.
//
// Input/output bit ordering:
//   rx_bits[0]      = first deinterleaved encoded bit received.
//   decoded_bits[0] = first decoded information/CRC bit.
//   Header uses decoded_bits[44:0]; CDS data uses decoded_bits[59:0].
//
// Interface:
//   mode_data = 0 -> Header, 90 coded bits -> 45 decoded bits
//   mode_data = 1 -> CDS data, 90 coded bits -> 60 decoded bits
//
// Notes:
//   * Hard-decision branch metrics are used.
//   * One trellis time is processed per clock, with 64 ACS units in parallel.
//   * The 64 candidate tail-biting start states are processed serially.
// -----------------------------------------------------------------------------
module link11_viterbi_decoder #(
    localparam integer PM_WIDTH = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  start,                // rx_bits有效标志
    input  logic                  mode_data,            // rx_bits类型
    input  logic [89:0]           rx_bits,              

    output logic                  busy,
    output logic                  done,
    output logic [59:0]           decoded_bits,
    output logic [5:0]            decoded_length,
    output logic [5:0]            best_start_state,
    output logic [PM_WIDTH-1:0]   best_path_metric
);

    localparam integer STATE_BITS = 6;
    localparam integer NUM_STATES = 1 << STATE_BITS;
    localparam integer MAX_STEPS  = 60;

    localparam logic [PM_WIDTH-1:0] INF_METRIC = {PM_WIDTH{1'b1}};

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_INIT_TRIAL,
        ST_ACS,
        ST_EVALUATE,
        ST_TRACEBACK,
        ST_FINISH
    } fsm_t;

    fsm_t state;

    logic        mode_data_q;
    logic [89:0] rx_bits_q;
    logic [5:0]  total_steps;
    logic [5:0]  step_index;
    logic [5:0]  trial_start_state;

    logic [PM_WIDTH-1:0] path_metric      [0:NUM_STATES-1];
    logic [PM_WIDTH-1:0] next_path_metric [0:NUM_STATES-1];

    // survivor_mem[t][s] = 0 selects predecessor {s[4:0],1'b0}
    //                    = 1 selects predecessor {s[4:0],1'b1}
    logic survivor_mem  [0:MAX_STEPS-1][0:NUM_STATES-1];
    logic next_survivor [0:NUM_STATES-1];

    logic [5:0] traceback_state;
    logic [5:0] traceback_index;
    logic       traceback_pred_sel;
    logic [5:0] traceback_prev_state;

    logic [1:0] rx_pair;
    logic [1:0] rx_mask;
    integer     rx_index_comb;

    integer s;
    integer prev0_int;
    integer prev1_int;
    logic input_bit_comb;
    logic [1:0] expected0_comb;
    logic [1:0] expected1_comb;
    logic [1:0] branch_metric0_comb;
    logic [1:0] branch_metric1_comb;
    logic [PM_WIDTH-1:0] candidate0_comb;
    logic [PM_WIDTH-1:0] candidate1_comb;

// 根据输入和当前状态计算输出
    // Full 7-bit encoder register is:
    //   {current_input, previous_state[5:0]}
    // where previous_state[5] is the newest stored bit.
    // Output [1] is T1 and output [0] is T2.
    function automatic logic [1:0] convolution_output(
        input logic [5:0] previous_state,
        input logic       current_input,
        input logic       data_mode
    );
        logic [6:0] encoder_register;
        logic [6:0] generator_t1;
        logic [6:0] generator_t2;
        begin
            encoder_register = {current_input, previous_state};

            if (data_mode) begin
                // (163,135)_oct
                generator_t1 = 7'b1110011;
                generator_t2 = 7'b1011101;
            end else begin
                // (133,171)_oct
                generator_t1 = 7'b1011011;
                generator_t2 = 7'b1111001;
            end
        // 组合逻辑延时点, 逐位异或(0.3～1.0 ns)后规约异或(0.7～1.5 ns)
            convolution_output[1] = ^(encoder_register & generator_t1);
            convolution_output[0] = ^(encoder_register & generator_t2);
        end
    endfunction
// 计算每步的每个时刻的汉明距离
    function automatic logic [1:0] hard_branch_metric(
        input logic [1:0] expected,
        input logic [1:0] received,
        input logic [1:0] valid_mask
    );
        logic mismatch_t1;
        logic mismatch_t2;
        begin
            mismatch_t1 = (expected[1] ^ received[1]) & valid_mask[1];
            mismatch_t2 = (expected[0] ^ received[0]) & valid_mask[0];
            hard_branch_metric = {1'b0, mismatch_t1}
                               + {1'b0, mismatch_t2};
        end
    endfunction
// 计算路径的距离总和
    function automatic logic [PM_WIDTH-1:0] saturating_metric_add(
        input logic [PM_WIDTH-1:0] metric,
        input logic [1:0]          branch_metric
    );
        logic [PM_WIDTH-1:0] branch_ext;
        begin
            branch_ext = {{(PM_WIDTH-2){1'b0}}, branch_metric};
            // 最主要的延时点, 比较和相加
            if ((metric == INF_METRIC) ||
                (metric >= (INF_METRIC - branch_ext))) begin
                saturating_metric_add = INF_METRIC;
            end else begin
                saturating_metric_add = metric + branch_ext;
            end
        end
    endfunction

    // Select the coded bits belonging to the current binary trellis step.
    always_comb begin
        rx_pair       = 2'b00;
        rx_mask       = 2'b00;
        rx_index_comb = 0;

        if (!mode_data_q) begin
            // Header: T1,T2 for every input bit.
            rx_index_comb = step_index * 2;
            rx_pair[1]    = rx_bits_q[rx_index_comb];
            rx_pair[0]    = rx_bits_q[rx_index_comb + 1];
            rx_mask       = 2'b11;
        end else if (step_index[0] == 1'b0) begin
            // CDS data, first step of each pair: T1,T2 are both transmitted.
            rx_index_comb = (step_index >> 1) * 3;
            rx_pair[1]    = rx_bits_q[rx_index_comb];
            rx_pair[0]    = rx_bits_q[rx_index_comb + 1];
            rx_mask       = 2'b11;
        end else begin
            // CDS data, second step of each pair: only T1 is transmitted.
            // The missing T2 is treated as an erasure.
            rx_index_comb = ((step_index >> 1) * 3) + 2;
            rx_pair[1]    = rx_bits_q[rx_index_comb];
            rx_pair[0]    = 1'b0;
            rx_mask       = 2'b10;
        end
    end

    // One complete 64-state ACS stage.
    // State update convention:
    //   next_state = {input_bit, previous_state[5:1]}
    // Therefore, for a fixed next state s:
    //   input_bit = s[5]
    //   prev0     = {s[4:0],1'b0}
    //   prev1     = {s[4:0],1'b1}
    always_comb begin
        for (s = 0; s < NUM_STATES; s = s + 1) begin
            prev0_int       = (s & (NUM_STATES/2 - 1)) << 1;    // 上个末尾为0的状态
            prev1_int       = prev0_int | 1;                    // 上个末尾为1的状态
            input_bit_comb  = (s >> (STATE_BITS-1)) & 1;        // 最高位, 即输入

            expected0_comb = convolution_output(                // 上个时刻的输出结果2bit
                prev0_int[STATE_BITS-1:0],
                input_bit_comb,
                mode_data_q
            );
            expected1_comb = convolution_output(                // 上个时刻的输出结果2比特
                prev1_int[STATE_BITS-1:0],
                input_bit_comb,
                mode_data_q
            );

            branch_metric0_comb = hard_branch_metric(           // 计算汉明距离
                expected0_comb, rx_pair, rx_mask
            );
            branch_metric1_comb = hard_branch_metric(           // 计算汉明距离
                expected1_comb, rx_pair, rx_mask
            );

            candidate0_comb = saturating_metric_add(            // 计算路径总距离
                path_metric[prev0_int], branch_metric0_comb
            );
            candidate1_comb = saturating_metric_add(            // 计算路径总距离
                path_metric[prev1_int], branch_metric1_comb
            );

            // Deterministic tie break: predecessor with LSB=0.
            if (candidate1_comb < candidate0_comb) begin        // 比较0, 1结尾的总距离, 取更小的那个作为当前时刻当前状态的幸存路径
                next_path_metric[s] = candidate1_comb;
                next_survivor[s]    = 1'b1;                     // 上个时刻, 来源状态抛弃的最低bit
            end else begin
                next_path_metric[s] = candidate0_comb;
                next_survivor[s]    = 1'b0;
            end
        end
    end

    always_comb begin
        traceback_pred_sel  = survivor_mem[traceback_index][traceback_state];
        traceback_prev_state = {traceback_state[4:0], traceback_pred_sel};
    end

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            mode_data_q         <= 1'b0;
            rx_bits_q           <= '0;
            total_steps         <= 6'd0;
            step_index          <= 6'd0;
            trial_start_state   <= 6'd0;
            traceback_state     <= 6'd0;
            traceback_index     <= 6'd0;

            busy                <= 1'b0;
            done                <= 1'b0;
            decoded_bits        <= '0;
            decoded_length      <= 6'd0;
            best_start_state    <= 6'd0;
            best_path_metric    <= INF_METRIC;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin          // 等待新来的一整个block
                    busy <= 1'b0;

                    if (start) begin
                        mode_data_q       <= mode_data;
                        rx_bits_q         <= rx_bits;
                        total_steps       <= mode_data ? 6'd60 : 6'd45;
                        decoded_length    <= mode_data ? 6'd60 : 6'd45;
                        decoded_bits      <= '0;
                        best_start_state  <= 6'd0;
                        best_path_metric  <= INF_METRIC;
                        trial_start_state <= 6'd0;
                        busy              <= 1'b1;
                        state             <= ST_INIT_TRIAL;
                    end
                end

                ST_INIT_TRIAL: begin    // 初始状态
                    // Force this trial to originate from one specific state.
                    for (i = 0; i < NUM_STATES; i = i + 1) begin
                        if (i == trial_start_state)
                            path_metric[i] <= {PM_WIDTH{1'b0}};
                        else
                            path_metric[i] <= INF_METRIC;
                    end

                    step_index <= 6'd0;
                    state      <= ST_ACS;
                end

                ST_ACS: begin           // 对同一时刻的每个状态进行 加, 比, 选, 直到走完所有步
                    for (i = 0; i < NUM_STATES; i = i + 1) begin
                        path_metric[i]                 <= next_path_metric[i];
                        survivor_mem[step_index][i]    <= next_survivor[i];
                    end

                    if (step_index == (total_steps - 1'b1)) begin
                        state <= ST_EVALUATE;
                    end else begin
                        step_index <= step_index + 1'b1;
                    end
                end
                                        // 走完所有步之后, 开始评估
                ST_EVALUATE: begin
                    // Tail-biting constraint: end state must equal start state.
                    if (path_metric[trial_start_state] < best_path_metric) begin        // 只拿起始状态的最幸路径与最佳路径对比
                        best_path_metric  <= path_metric[trial_start_state];            // 最幸路径距离
                        best_start_state  <= trial_start_state;                         // 最佳起始状态
                        traceback_state   <= trial_start_state;                         // 最佳结束状态
                        traceback_index   <= total_steps - 1'b1;                        // 倒数第一步, 对应最高位
                        state             <= ST_TRACEBACK;
                    end else if (trial_start_state == (NUM_STATES-1)) begin             // 已经找到所有可能状态的最佳路径
                        state <= ST_FINISH;
                    end else begin                                                      // 0~63还有状态没找完
                        trial_start_state <= trial_start_state + 1'b1;
                        state             <= ST_INIT_TRIAL;
                    end
                end

                ST_TRACEBACK: begin     // 一步一个时钟, 有效位从0开始往高了数
                    // The bit entering a state is that state's MSB.
                    // decoded_bits[traceback_index] <= traceback_state[STATE_BITS-1];     
                    decoded_bits[total_steps - 1'b1 - traceback_index]
                        <= traceback_state[STATE_BITS-1];                               // 状态的最高位是最近输入的1bit

                    if (traceback_index == 0) begin                                     // 完成了一个状态的最后1bit traceback
                        if (trial_start_state == (NUM_STATES-1)) begin                  // 完成了最后一个初始状态的轮询
                            state <= ST_FINISH;
                        end else begin                                                  // 开始下一个初始状态的轮询
                            trial_start_state <= trial_start_state + 1'b1;
                            state             <= ST_INIT_TRIAL;
                        end
                    end else begin                                                      // traceback过程中
                        traceback_state <= traceback_prev_state;                        // 按步回溯每一步的最佳state
                        traceback_index <= traceback_index - 1'b1;                      // 按步和最佳state回溯最幸路径上每个时刻的输入
                    end
                end

                ST_FINISH: begin        
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
