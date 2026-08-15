# Link 11 SLEW FPGA Modem

[![HDL](https://img.shields.io/badge/HDL-Verilog%20%7C%20SystemVerilog-blue)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Vivado](https://img.shields.io/badge/Vivado-2024.1-orange)](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html)
[![License](https://img.shields.io/badge/License-Apache--2.0-green.svg)](LICENSE)

[简体中文](README.zh-CN.md)

An open-source, synthesizable FPGA implementation of a Link 11 SLEW transmit and receive chain. The repository focuses on the modem data path: framing, channel coding, scrambling, waveform generation, synchronization, frequency correction, demodulation, Viterbi decoding, and CRC verification.

The design targets AMD/Xilinx Vivado and uses explicit strobe signals to process sample-rate data in a faster system clock domain. It is intended for interoperability research, protocol education, and reusable FPGA modem development.

The receive architecture was developed through two months of Codex-assisted design, simulation, and repeated on-board FPGA tuning. It has completed end-to-end hardware debugging in the maintainer's test setup, but has not yet been independently reproduced.

> [!IMPORTANT]
> This is an independent research implementation. It has not been certified for standards conformance, operational deployment, safety-critical use, or security-critical use. Protocol standards and vendor IP are not redistributed by this repository.

## Highlights

- Synthesizable transmit and receive data paths.
- Receive data path iterated and verified through on-board FPGA testing.
- 2,400 baud SLEW framing with a 192-symbol preamble and reinsertion probes.
- Header and data CRC-12 generation/checking.
- Tail-biting convolutional encoding and Viterbi decoding.
- QPSK mapping, 160-symbol scrambling, and IQ waveform generation.
- Symbol-boundary acquisition, preamble correlation, and fine frequency-offset correction.
- Simulation channel model with configurable carrier offset, AWGN, and a delayed multipath component.
- Parameterized sample ratio and data widths, with latency-aware reusable arithmetic modules.
- A Tcl script that reconstructs the Vivado project and required Xilinx IP.

## Hardware validation

The complete transmit-to-receive loopback has passed on an AMD/Xilinx ZU47DR in the maintainer's current lab setup. For the validated test vectors:

- The transmitter waveform was received and decoded end to end on hardware.
- The recovered coded/interleaved stream had zero observed bit errors.
- The reported Viterbi best-path metric remained `0`, consistent with an error-free coded stream.

This result is the product of two months of engineer-Codex co-design, followed by simulation, repeated on-board measurements, timing alignment, and architecture optimization. It exceeded the protocol-performance target in the tested loopback case. It is not presented as a general state-of-the-art claim until standardized impaired-channel sweeps, comparable baselines, and independent reproduction are available.

The zero-error result also means that interleaving and Viterbi error correction were not exercised by this clean loopback. Those protocol features remain necessary for channels with noise, fading, interference, or burst errors.

## Architecture

```text
Transmit
raw blocks -> CRC/convolutional encoder -> frame scheduler -> QPSK/scrambler -> 1800 Hz IQ waveform

Receive
IQ samples -> DDC/envelope detector -> symbol alignment -> preamble correlation
           -> fine frequency correction -> descrambler/QPSK -> deinterleave/Viterbi/CRC
```

The receive implementation is divided into numbered processing stages:

| Stage | Function |
| --- | --- |
| `link11_slew_step1` | 1,800 Hz downconversion, low-pass integration, and envelope detection |
| `link11_slew_step2` | Symbol-boundary search and aligned sample replay |
| `link11_slew_step4` | Preamble correlation, peak search, and preamble alignment |
| `link11_slew_step5` | Symbol accumulation, derotation, and fine frequency correction |
| `link11_slew_step6` | Descrambling and QPSK hard decisions |
| `link11_slew_step7` | Deinterleaving, tail-biting Viterbi decoding, and CRC checking |

Stage 3 is intentionally bypassed in the current top level. Frequency correction is performed after preamble alignment in stage 5.

## Repository layout

| Path | Contents |
| --- | --- |
| `link11_slew_demod_top.sv` | Receive top level |
| `tx/link11_slew_tx.sv` | Synthesizable transmit top level |
| `link11_slew_step*.sv` | Receive pipeline stages |
| `general/` | Reusable arithmetic, RAM, decoder, and frequency-correction modules |
| `simulate/` | End-to-end and focused simulation sources |
| `scripts/create_project.tcl` | Reproducible Vivado project and IP creation |
| `docs/module.md` | Reusable-module index, parameters, latency, and integration notes |

## Requirements

- AMD/Xilinx Vivado 2024.1. Newer releases may upgrade the generated IP.
- A device supported by the DDS Compiler 6.0 and CORDIC 6.0 IP catalogs.
- SystemVerilog support.

The reference project uses `xczu47dr-ffve1156-2-i`. The RTL is not board-specific, but resource use and IP latency must be revalidated when changing device family or Vivado version.

## Quick start

From the repository root, create a fresh Vivado project:

```powershell
vivado -mode batch -source scripts/create_project.tcl
```

To select another target part or output directory:

```powershell
vivado -mode batch -source scripts/create_project.tcl -tclargs xczu47dr-ffve1156-2-i build/link11_slew
```

Open the generated project:

```powershell
vivado build/link11_slew/link11_slew.xpr
```

The script sets `link11_slew_demod_top` as the synthesis top and `link11_slew_simulate` as the simulation top. Set `link11_slew_tx` as the synthesis top when integrating the transmitter alone.

## Top-level interfaces

### Receiver: `link11_slew_demod_top`

Key parameters:

| Parameter | Default | Meaning |
| --- | ---: | --- |
| `DATA_WIDTH` | 16 | Input I/Q and threshold width |
| `WINDOW_NUM` | 64 | Input samples per 2,400 baud symbol |
| `STANDARD_1800_PHASE_INC` | 1600 | 16-bit phase increment, calculated as `round(1800 * 65536 / sample_rate)` |

The input stream uses `signal_if_strobe` with two's-complement `signal_if_i/q`. Decoded blocks are reported through `decoded_bits`, `decoded_length`, `viterbi_done`, `crc_check_pass`, and `crc_check_strobe`. `device_type` selects PICKET (`1`) or NCS (`0`) frame handling.

### Transmitter: `link11_slew_tx`

Key parameters:

| Parameter | Default | Meaning |
| --- | ---: | --- |
| `SAMPLE_CLK_NUM` | 1 | System clocks per output IQ sample |
| `SYMBOL_SAMPLE_NUM` | 32 | IQ samples per 2,400 baud symbol |
| `CARRIER_PHASE_INC` | 1536 | 16-bit 1,800 Hz carrier phase increment |

Load header index `0` and data block indices `1..15` through `raw_data_valid`, then pulse `start_tx`. Output samples are valid when `tx_strobe` is asserted. `busy`, `done`, and `tx_enable` delimit the frame.

## Latency and integration notes

- Reset is synchronous and active low (`rst_n`) throughout the maintained data paths.
- The design is latency sensitive. Do not change arithmetic or Xilinx IP pipeline settings without realigning the corresponding strobe/control paths.
- DDS Compiler latency is fixed to 7 clocks in the reconstruction script. CORDIC uses maximum pipelining, so its exact latency depends on the selected device and generated IP.
- Most low-rate pipelines advance only when their strobe or clock-enable input is asserted. A latency expressed in valid samples is not necessarily the same number of system clocks.
- Width reductions normally take the high bits to preserve signed scaling. Review every truncation after changing a width parameter.
- See [`docs/module.md`](docs/module.md) before reusing or modifying a module under `general/`.

## Simulation

`simulate/link11_slew_simulate.sv` connects the simulation transmitter and receiver. Its parameters cover carrier-frequency offset, noise, multipath, symbol sampling, and data-block count.

### Representative receive-chain waveforms

The following Vivado waveform captures document internal signals from one representative end-to-end simulation run. They are included as implementation and debugging evidence rather than as an independent conformance benchmark. The images are preserved without altering the displayed waveforms or values.

**1. IF input and zero-IF conversion.** The 1,800 Hz intermediate-frequency I/Q input is mixed down to the synchronized zero-IF I/Q signals used by the receive pipeline.

![IF input and zero-IF conversion](docs/images/simulation-01-if-to-zero-if.png)

**2. Zero-IF envelope and sliding-window energy.** The filtered zero-IF I/Q envelopes feed the accumulated energy calculation used by the acquisition stages.

![Zero-IF envelope and sliding-window energy](docs/images/simulation-02-envelope-energy.png)

**3. Symbol alignment and preamble acquisition.** Aligned I/Q samples are evaluated by the preamble correlator; the correlation and integrated peak metrics identify the block-alignment point.

![Symbol alignment and preamble acquisition](docs/images/simulation-03-symbol-preamble-alignment.png)

**4. Preamble-referenced phase correction.** The aligned preamble drives DDS-based phase correction, producing frequency-corrected I/Q samples and the data stream presented to the demodulation stage.

![Preamble-referenced phase correction](docs/images/simulation-04-phase-frequency-correction.png)

In Vivado:

1. Run `scripts/create_project.tcl`.
2. Open the generated project.
3. Select `link11_slew_simulate` as the simulation top.
4. Run behavioral simulation and inspect `crc_check_strobe`, `crc_check_pass`, and `decoded_bits`.

The simulation models are development aids rather than an independent conformance test suite. Contributions that add self-checking vectors and coverage are especially welcome.

## Contributing and security

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report vulnerabilities according to [SECURITY.md](SECURITY.md), without placing sensitive details in a public issue.

## License

Original source code in this repository is licensed under the [Apache License 2.0](LICENSE). Third-party specifications, Xilinx IP, and generated vendor artifacts are governed by their respective terms and are not included.
