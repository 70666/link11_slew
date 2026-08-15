# Codex for Open Source application draft

Official application: https://openai.com/form/codex-for-oss/

Replace every bracketed placeholder and verify repository metrics immediately before submission. Each long-form answer below is kept under the form's 500-character limit.

## Applicant information

- First name: `[your first name]`
- Last name: `[your last name]`
- Email associated with ChatGPT: `[your ChatGPT email]`
- GitHub username: `70666`
- GitHub repository URL: `https://github.com/70666/link11_slew`
- Role: `Primary maintainer`
- Interested in: `API credits for my project`
- OpenAI organization ID: `[org-...]`

Select `Codex Security` only if you have a concrete repository-security workflow and are prepared to explain it.

## Why does this repository qualify?

### English

I am the primary maintainer of an open FPGA implementation of the Link 11 SLEW modem data path. It makes a specialized legacy interoperability protocol reproducible and inspectable for research and education, covering synthesis-ready TX/RX RTL, synchronization, frequency correction, channel coding, Viterbi decoding, CRC, simulation models, and a reproducible Vivado build. I actively maintain timing alignment, verification, documentation, and contributor review.

### 中文参考

我是该项目的主要维护者. 项目开源实现 Link 11 SLEW FPGA 调制解调数据链路, 为专用传统互操作协议提供可复现, 可审查的研究与教学实现. 仓库包含可综合 TX/RX RTL, 同步, 频偏校正, 信道编码, Viterbi 译码, CRC, 信道仿真和可复现 Vivado 构建. 我持续负责延时对齐, 验证, 文档和贡献审核.

## How will you use API credits for your project?

### English

I will use API credits for maintainer automation: reviewing RTL pull requests for data/control latency mismatches, generating focused SystemVerilog testbenches, triaging simulation failures, checking parameterized widths and signed truncation, improving module documentation, and preparing release notes. Human review and Vivado simulation/synthesis will remain required before changes merge, especially for protocol behavior and timing-sensitive pipelines.

### 中文参考

我会将 API credits 用于维护自动化: 审查 RTL Pull Request 中的数据和控制延时错位, 生成针对性 SystemVerilog testbench, 分析仿真失败, 检查参数化位宽和有符号截位, 完善模块文档和生成发布说明. 合并前仍要求人工审核及 Vivado 仿真/综合, 尤其关注协议行为和延时敏感流水线.

## Anything else we should know?

### English

The project is intentionally source-first: proprietary standards and generated vendor artifacts are excluded, while a Tcl flow recreates required Xilinx IP. Codex would reduce the unusually high review cost of HDL changes, where a one-cycle strobe mismatch can silently corrupt an otherwise correct algorithm. Support would help me add self-checking vectors, CI-friendly verification, issue triage, and contributor guidance for a niche area with limited open implementations.

### 中文参考

项目坚持 source-first: 不分发受版权保护的标准和厂商生成文件, 使用 Tcl 重建所需 Xilinx IP. HDL 修改的审核成本很高, 一拍 strobe 错位就可能让正确算法静默出错. Codex 支持将帮助我增加自检向量, CI 友好验证, Issue 分类和贡献者指南, 改善这个公开实现较少的专用方向.

## Evidence to add before submission

Use only verifiable facts. Do not invent adoption metrics.

- Current stars, forks, watchers, and unique cloners.
- Any university, laboratory, company, course, paper, board port, or downstream project that actually uses the repository.
- Recent issues, pull-request reviews, releases, and maintenance activity.
- A short roadmap issue and a first tagged release.
- A public GitHub profile and enabled private vulnerability reporting.

If the repository has little public adoption, say so honestly and emphasize ecosystem importance, reproducibility, maintenance responsibility, and the scarcity of comparable open FPGA implementations. The program explicitly allows projects that do not fit neatly to explain their importance.
