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

I am the primary maintainer of this open Link 11 SLEW FPGA modem. FPGA verification requires costly boards, long build cycles, and lab debugging. Over two months, I used Codex to explore an unfamiliar demodulation architecture, then implemented, tuned, and verified it on hardware. Publishing the resulting TX/RX RTL, timing knowledge, simulation models, and reproducible Vivado flow helps others avoid repeating expensive experiments in a niche with few open implementations.

### 中文参考

我是这个 Link 11 SLEW FPGA 调制解调器的主要维护者. FPGA 验证需要昂贵的硬件, 很长的构建周期和实验室调试. 两个月来, 我使用 Codex 探索不熟悉的解调架构, 再亲自实现, 调优并上板验证. 公开 TX/RX RTL, 延时知识, 信道仿真和可复现 Vivado 流程, 可以帮助其他工程师避免在公开实现稀缺的方向重复昂贵试验.

## How will you use API credits for your project?

### English

I will use API credits for maintainer automation: reviewing RTL pull requests for data/control latency mismatches, generating focused SystemVerilog testbenches, triaging simulation failures, checking parameterized widths and signed truncation, improving module documentation, and preparing release notes. Human review and Vivado simulation/synthesis will remain required before changes merge, especially for protocol behavior and timing-sensitive pipelines.

### 中文参考

我会将 API credits 用于维护自动化: 审查 RTL Pull Request 中的数据和控制延时错位, 生成针对性 SystemVerilog testbench, 分析仿真失败, 检查参数化位宽和有符号截位, 完善模块文档和生成发布说明. 合并前仍要求人工审核及 Vivado 仿真/综合, 尤其关注协议行为和延时敏感流水线.

## Anything else we should know?

### English

Codex is often perceived as a software-only tool, so many hardware and FPGA engineers underuse it despite exceptionally high debugging costs. This project demonstrates a rigorous human-Codex workflow: architecture discussion, RTL implementation, simulation, on-board testing, measurement-driven optimization, and repeated review. Support would help turn two months of lab-tested knowledge into self-checking vectors, maintainable releases, and practical guidance for the wider FPGA community.

### 中文参考

Codex 常被认为只适合软件工程师, 因此许多硬件和 FPGA 工程师低估了它, 但硬件调试成本尤其高. 这个项目展示了严格的人机协作闭环: 架构讨论, RTL 实现, 仿真, 上板测试, 测量驱动优化和反复审核. 支持将帮助我把两个月的实验室验证知识转化为自检向量, 可维护版本和面向更广泛 FPGA 社区的实践指南.

## Evidence to add before submission

Use only verifiable facts. Do not invent adoption metrics.

- Current stars, forks, watchers, and unique cloners.
- Any university, laboratory, company, course, paper, board port, or downstream project that actually uses the repository.
- Recent issues, pull-request reviews, releases, and maintenance activity.
- A short roadmap issue and a first tagged release.
- A public GitHub profile and enabled private vulnerability reporting.

If the repository has little public adoption, say so honestly and emphasize ecosystem importance, reproducibility, maintenance responsibility, and the scarcity of comparable open FPGA implementations. The program explicitly allows projects that do not fit neatly to explain their importance.
