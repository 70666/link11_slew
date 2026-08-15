# general 模块索引

本文件用于让后续维护者和 AI 快速选择通用模块, 避免反复通读 `general` 目录源码.
新增通用模块后, 必须同步补充用途, 关键参数, 延时和使用注意.

## 命名规则

- `*_CE`: 带 `clock_enable` 的变体, 只有使能有效时流水线推进.
- `*_strobe`: 带输入 strobe 的变体, 输出通常带对齐后的 strobe.
- 数学模块的 `A_TYPE/B_TYPE/DATA_TYPE`: `1` 表示 signed, `0` 表示 unsigned.
- 数学模块的 `OUT_WIDTH`: 多数模块输出取低 `OUT_WIDTH` 位, 使用前要确认是否会丢符号位或高位有效信息.

## general/mathematic

### `Adder`

- 用途: 两输入加法, 支持 LUT/DSP 实现, 支持 signed/unsigned 输入扩展.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`, `IMPL_TYPE`.
- 延时: `LATENCY` clks.
- 注意: 端口名为 `SUM`, 输出声明为 signed. 作为通用三则运算模块使用, 避免直接写组合加法.

### `Subtracter`

- 用途: 两输入减法, 支持 LUT/DSP 实现, 支持 signed/unsigned 输入扩展.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`, `IMPL_TYPE`.
- 延时: `LATENCY` clks.
- 注意: 端口名为 `SUM`, 实际语义是 `A - B`.

### `multiplier`

- 用途: 两输入乘法, 支持 LUT/DSP 实现, 支持 signed/unsigned 输入扩展.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`, `IMPL_TYPE`.
- 延时: `LATENCY` clks.
- 注意: 输出取低 `OUT_WIDTH` 位. 若乘法结果后续需要等比例缩放, 一般应在外部取高位.

### `AdderTree`

- 用途: 多输入加法树, 基于 `Adder` 递归二分流水实现.
- 关键参数: `DATA_WIDTH`, `DATA_TYPE`, `OUT_WIDTH`, `LATENCY`, `DATA_NUM`, `IMPL_TYPE`.
- 延时: `LATENCY * $clog2(DATA_NUM)` clks.
- 注意: 输出取低 `OUT_WIDTH` 位. `DATA_NUM` 最好取 2 的幂, 非 2 的幂使用前需要重点验证.

### `UnsignedAdderTreePipelined`

- 用途: 多输入无符号流水加法树, `in_advance` 控制流水线是否推进.
- 关键参数: `DATA_WIDTH`, `LENGTH`, `DELAY_STAGES`.
- 延时: 约为 `DELAY_STAGES` 个 `in_advance` 有效周期.
- 注意: 只适合 unsigned 数据. 同名模块在 `general/mathematic` 和 `general/clock_enable` 下各有一份.

### `moving_sum`

- 用途: 对 I/Q 两路分别求最近 `WINDOW_NUM` 个采样点的窗口和.
- 关键参数: `DATA_WIDTH`, `WINDOW_NUM`, `LATENCY`.
- 延时: 输出数据为 `$clog2(WINDOW_NUM) * LATENCY` clks, `data_out_strobe` 当前实现多 1 clk, 即 `$clog2(WINDOW_NUM) * LATENCY + 1` clks.
- 注意: 使用 `AdderTree` 做窗口和, 输入 strobe 低时窗口寄存器不推进.

### `complex_to_mag`

- 用途: 对 signed I/Q 做粗略幅度估计, 使用近似公式 `max(abs(I), abs(Q)) + min(abs(I), abs(Q))/4`.
- 关键参数: `DATA_WIDTH`.
- 延时: 3 clks.
- 注意: 输入使用 `input_strobe`, 输出 `mag_stb` 对齐幅度结果.

### `mixer`

- 用途: 复数乘法/混频. `MODE=0` 表示相位相减, `MODE=1` 表示相位相加.
- 关键参数: `A_DATA_WIDTH`, `B_DATA_WIDTH`, `IMPL_TYPE`, `MODE`.
- 延时: 7 clks.
- 注意: 输出宽度为 `A_DATA_WIDTH + B_DATA_WIDTH + 1`. 假设工程环境是正交的IQ, 那么这个最高位是一定可以舍去的.实际有效位宽为低A_DATA_WIDTH + B_DATA_WIDTH位

### `mixer_strobe`

- 用途: 带 strobe 的 `mixer`, 只在 `in_strobe` 有效时采样输入, 输出 `out_strobe` 对齐结果.
- 关键参数: `A_DATA_WIDTH`, `B_DATA_WIDTH`, `IMPL_TYPE`, `MODE`.
- 延时: 7 clks.
- 注意: 复位释放后内部会等待 strobe 延时管线灌 0, 避免未知 strobe 输出.

### `DDC`

- 用途: 使用 `lut_sin` 生成标准参考波, 再用 `mixer` 下变频.
- 关键参数: `DATA_WIDTH`, `DDS_PATTERN_WIDTH`, `DDS_PHASE_WIDTH`, `STANDARD_DDC_PHASE_INC`.
- 延时: `lut_sin` 对相位有 7 个样本延时和 1 clk 输入延时, 下变频 `mixer` 另有 7 clks.
- 注意: `data_in_storbe` 端口名存在拼写问题, 例化时按现有端口名连接.

## general/mathematic_strobe

### `Adder_strobe`

- 用途: 带 `data_in_strobe` 的两输入加法, 输出 `data_out_strobe` 对齐 `SUM`.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`, `IMPL_TYPE`.
- 延时: `LATENCY` clks.
- 注意: 输出为 signed. 若用它做反馈累加, 输入 strobe 间隔必须大于等于加法反馈需要的间隔, 否则前一次结果还没返回就会被下一次使用.

## general/misc

### `delay`

- 用途: 固定 clk 延时线.
- 关键参数: `DATA_WIDTH`, `DELAY_CLK`, `IMPL_TYPE`.
- 延时: `DELAY_CLK` clks.
- 注意: 无复位, 上电或复位后前 `DELAY_CLK` 拍可能为未知值. `IMPL_TYPE=0` 为 FF, `IMPL_TYPE=2` 为 SRL.

### `delay_CE`

- 用途: 带 `clock_enable` 的固定延时线.
- 关键参数: `DATA_WIDTH`, `DELAY_CLK`, `IMPL_TYPE`.
- 延时: `DELAY_CLK` 个 `clock_enable` 有效周期.
- 注意: 适合低速有效数据对齐, 使能无效时延时线保持.

### `strobe_delay`

- 用途: 对带 `strobe_in` 的低速数据做可变 strobe 周期延时.
- 关键参数: `DELAY_W`, `DATA_W`, `MAX_DELAY`.
- 延时: `delay` 个有效 strobe 周期, 另外有 1 个 clk 输出寄存延时.
- 注意: `delay` 不能超过 `MAX_DELAY`. 输出 `strobe_out` 与 `signal_out` 对齐.

### `edge_detect`

- 用途: 检测单 bit 信号上升沿和下降沿.
- 关键参数: `NO_LATENCY`.
- 延时: 根据 `NO_LATENCY` 选择是否增加检测寄存延时.
- 注意: 输出 `flag_pos` 和 `flag_neg` 为边沿脉冲.

### `envelope_detector`

- 用途: 对多通道输入做包络门限检测, 并把原始信号延时到与 `envelope` 对齐.
- 关键参数: `BIT_ENVELOPE_DETECTION`, `DETECTION_CLOCK_NUM`, `DETECTION_HIGH_NUM`, `CHANNEL_NUM`.
- 延时: 平方和 5 clks, 滑动窗口 1 clk, 判决统计 `$clog2(DETECTION_CLOCK_NUM)` clks, 输出对齐约 `DETECTION_HIGH_NUM + 1` clks.
- 注意: `signal_out` 已对齐检测结果, 下游不要再重复补这些延时.

### `envelope_detector_strobe`

- 用途: 带 `clock_enable` 的包络检测变体.
- 关键参数: `DATA_WIDTH`, `BIT_ENVELOPE_DETECTION`, `DETECTION_CLOCK_NUM`, `DETECTION_HIGH_NUM`, `CHANNEL_NUM`.
- 延时: 与 `envelope_detector` 的各级延时一致, 但按 `clock_enable` 有效周期推进.
- 注意: 输出 `clock_enable_out` 与 `envelope` 和 `signal_out` 对齐.

### `lut_sin`

- 用途: 通过 DDS/LUT 生成 sin/cos. 支持 `"PRELOAD"` 预加载数组和 `"RUNTIME"` 实时输出.
- 关键参数: `WORKING_MODE`, `PHASE_WIDTH`, `DATA_WIDTH`, `PRELOAD_LENGTH`.
- 延时: `"RUNTIME"` 模式为 1 个输入 clk 延时 + 7 个样本延时. 7 个样本延时不是 7 个 clk 延时, 而是输出相位相对输入相位的样本延时.
- 注意: `PHASE_WIDTH` 和 `DATA_WIDTH` 最大按 16 使用.

## general/clock_enable

### `Adder_CE`

- 用途: 带 `clock_enable` 的 `Adder` 变体.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`, `IMPL_TYPE`.
- 延时: `LATENCY` 个 `clock_enable` 有效周期.
- 注意: 输出为 signed, 使能无效时流水线保持.

### `multiplier_CE`

- 用途: 带 `clock_enable` 的 `multiplier` 变体.
- 关键参数: `A_WIDTH`, `B_WIDTH`, `A_TYPE`, `B_TYPE`, `OUT_WIDTH`, `LATENCY`.
- 延时: `LATENCY` 个 `clock_enable` 有效周期.
- 注意: 输出取低 `OUT_WIDTH` 位.

### `UnsignedAdderTreePipelined`

- 用途: 带推进使能的无符号加法树.
- 关键参数: `DATA_WIDTH`, `LENGTH`, `DELAY_STAGES`.
- 延时: 约为 `DELAY_STAGES` 个 `in_advance` 有效周期.
- 注意: 只适合 unsigned 数据.

## general/ram_wrapper

### `sdpram_wrapper`

- 用途: 同步时钟双口 RAM 包装, A 口写, B 口读.
- 关键参数: `WRITE_WIDTH`, `WRITE_DEPTH`, `READ_WIDTH`, `RAM_LATENCY`.
- 延时: B 口读延时为 `RAM_LATENCY` clks.
- 注意: `WRITE_WIDTH` 和 `READ_WIDTH` 可以不同, 地址宽度由深度和位宽比例自动计算.

## general/decoder

### `viterbi_decoder`

- 用途: 硬判决 Viterbi 译码器, 默认码率 1/2, 约束长度 K=7, 生成多项式 171/133(octal).
- 关键参数: `CONSTRAINT_LEN`, `POLY_0`, `POLY_1`, `TRACEBACK_DEPTH`, `METRIC_WIDTH`, `ADD_LATENCY`, `SUB_LATENCY`.
- 延时: 接收 1 个码字后的路径度量更新延时为 `ADD_LATENCY + 1 + SUB_LATENCY` clks. `out_strobe` 相对已接收码字流约延时 `TRACEBACK_DEPTH` 个有效码字.
- 注意: 上游必须看 `in_ready`; 只有 `in_ready=1` 时 `in_strobe` 才会被接收. `rx_bits[1]` 对应 `POLY_0`, `rx_bits[0]` 对应 `POLY_1`.

## project modules

### `cordic_arctan_data_format`

- 用途: 将 signed I/Q 共同左移归一化后适配为 CORDIC arctan IP 的 SignedFraction 输入格式, 输出 AXI-stream cartesian `tdata = {q, i}` 和对齐 `tvalid`.
- 关键参数: `IQ_WIDTH`, `CORDIC_WIDTH`.
- 延时: 1 clk.
- 注意: I/Q 使用相同左移量, 该左移量取两路可左移量的较小值, 保持 IQ 比例不变. 左移目标是让有效最高位尽量靠近 CORDIC 输入次高位, 即最高两位尽量形成 `01` 或 `10`. `IQ_WIDTH >= CORDIC_WIDTH` 时取归一化后的高 `CORDIC_WIDTH` 位, `IQ_WIDTH < CORDIC_WIDTH` 时在低位补 0. 本模块不做饱和, 若输入本身已经超出可表示范围, 下游需要重点审核 CORDIC 输出行为.

### `link11_slew_step4_symbol_average`

- 用途: 按 symbol 边界对零中频 I/Q 取平均, 为前导码相关提供每 symbol 一个复数采样.
- 关键参数: `LPF_WIDTH`, `WINDOW_NUM`.
- 延时: `$clog2(AVERAGE_SAMPLE_NUM) + 1` clks.
- 注意: `AVERAGE_SAMPLE_NUM` 取不超过 `WINDOW_NUM-1` 的最大 2 次幂, 输出通过取累加结果高位完成等比例缩放.

### `link11_slew_step4_preamble_correlator`

- 用途: 将连续三个 symbol 平均值与已知索引 3, 4, 5 的前导序列做复相关.
- 关键参数: `LPF_WIDTH`, `PREAMBLE_SYMBOL_NUM`.
- 延时: 9 clks.
- 注意: 第一个输出对应窗口 1~3, 后续每个输出窗口向后移动一个 symbol. 本模块不生成或传递 symbol 索引.

### `link11_slew_step4_peak_search`

- 用途: 在前导码搜索区间内寻找相关峰值, 输出前导码起点偏移和归一化初相参考.
- 关键参数: `LPF_WIDTH`, `PREAMBLE_SYMBOL_NUM`.
- 延时: 相关幅度对齐 3 clks, 搜索结束后逐拍左移归一化, 归一化延时取决于相关向量有效位位置.
- 注意: 模块内部从窗口末尾索引 3 开始顺序计数, 不依赖上游传递索引. 已知三个 symbol 的最后一个映射到索引 5, 输出起点偏移单位为 symbol.

### `link11_slew_step4_data_corrector`

- 用途: 缓存粗频偏校正数据, 从前导码起点回放并减去公共初相.
- 关键参数: `LPF_WIDTH`, `WINDOW_NUM`, `PREAMBLE_SYMBOL_NUM`.
- 延时: 地址乘法 2 clks, RAM 读取 2 clks, 初相混频 7 clks, 合计 11 clks.
- 注意: 初相参考有效后仍需要输入 strobe 持续到来, 以相同速率推进缓存回放.

### `link11_slew_step4`

- 用途: 连接 symbol 平均, 前导相关, 峰值搜索和初相校正四个功能模块.
- 关键参数: `LPF_WIDTH`, `WINDOW_NUM`, `PREAMBLE_SYMBOL_NUM`.
- 延时: 需要完成 `PREAMBLE_SYMBOL_NUM` 个 symbol 搜索和逐拍初相归一化, 参考有效后到首个校正输出另有 11 clks 数据通路延时.
- 注意: `preamble_aligned_start` 仅在首个初相校正输出有效时拉高 1 clk.
