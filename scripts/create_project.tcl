# Recreate the Link 11 SLEW Vivado project from tracked source files.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set part_name [expr {$argc >= 1 ? [lindex $argv 0] : "xczu47dr-ffve1156-2-i"}]
set project_dir [expr {$argc >= 2 ? [file normalize [lindex $argv 1]] : [file join $repo_dir build link11_slew]}]

create_project -force link11_slew $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_relpaths [list \
    general/mathematic/Adder.v \
    general/mathematic_strobe/Adder_strobe.v \
    general/mathematic/Subtracter.v \
    general/mathematic/complex_to_mag.v \
    general/misc/edge_detect.v \
    general/mathematic_strobe/mixer_strobe.v \
    general/mathematic/multiplier.v \
    general/ram_wrapper/sdpram_wrapper.v \
    general/mathematic_strobe/square_sum_strobe.v \
    general/clock_enable/envelope_detector_strobe.sv \
    general/mathematic/AdderTree.sv \
    general/mathematic/DDC.sv \
    general/decoder/crc_check.sv \
    general/misc/delay.sv \
    general/clock_enable/delay_CE.sv \
    general/freq_correction/freq_correction.sv \
    general/freq_correction/freq_diff_correct.sv \
    general/freq_correction/freq_estimation.sv \
    general/freq_correction/init_phase_correct.sv \
    general/freq_correction/ram_cache.sv \
    general/misc/link11_tone_ref_dds.sv \
    general/misc/lut_sin.sv \
    general/mathematic/moving_sum.sv \
    general/mathematic_strobe/normalize.sv \
    general/decoder/qpsk_decoder.sv \
    link11_slew_step1.sv \
    link11_slew_step2.sv \
    link11_slew_step2_param_align.sv \
    link11_slew_step2_peak_finder.sv \
    link11_slew_step4.sv \
    link11_slew_step4_peak_search.sv \
    link11_slew_step4_preamble_correlator.sv \
    link11_slew_step4_ram_cache.sv \
    link11_slew_step4_symbol_average.sv \
    link11_slew_step4_window_correlator.sv \
    link11_slew_step5.sv \
    link11_slew_step5_derot.sv \
    link11_slew_step5_samples_to_symbol.sv \
    link11_slew_step6.sv \
    link11_slew_step6_scrambler.sv \
    link11_slew_step7.sv \
    link11_slew_step7_crc_check.sv \
    link11_slew_step7_deinterleave.sv \
    link11_slew_step7_flow_ctrl.sv \
    link11_slew_sync_ram_cache.sv \
    link11_viterbi_decoder.sv \
    scrambler_lut.sv \
    link11_slew_demod_top.sv \
    tx/link11_slew_tx_block_encoder.sv \
    tx/link11_slew_tx_frame_builder.sv \
    tx/link11_slew_tx_symbol_scheduler.sv \
    tx/link11_slew_tx_raw_data.sv \
    tx/link11_slew_tx_waveform.sv \
    tx/link11_slew_tx.sv]

set sim_relpaths [list \
    simulate/link11_slew_tx_block_encoder_sim.sv \
    simulate/link11_slew_tx_digital_sim.sv \
    simulate/link11_slew_tx_waveform_sim.sv \
    simulate/link11_slew_tx_top_sim.sv \
    simulate/link11_slew_simulate.sv]

set rtl_files {}
foreach relpath $rtl_relpaths {
    set fullpath [file join $repo_dir $relpath]
    if {![file exists $fullpath]} {
        error "Missing RTL source: $relpath"
    }
    lappend rtl_files $fullpath
}
add_files -norecurse -fileset sources_1 $rtl_files

set sim_files {}
foreach relpath $sim_relpaths {
    set fullpath [file join $repo_dir $relpath]
    if {![file exists $fullpath]} {
        error "Missing simulation source: $relpath"
    }
    lappend sim_files $fullpath
}
add_files -norecurse -fileset sim_1 $sim_files

set include_dirs [list \
    $repo_dir \
    [file join $repo_dir tx] \
    [file join $repo_dir simulate] \
    [file join $repo_dir general freq_correction cooperative_module]]
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property include_dirs $include_dirs [get_filesets sim_1]

# DDS phase-correction latency is 7 enabled clocks.
create_ip -name dds_compiler -vendor xilinx.com -library ip -version 6.0 -module_name dds_phase_correction
set_property -dict [list \
    CONFIG.PartsPresent {Phase_Generator_and_SIN_COS_LUT} \
    CONFIG.Parameter_Entry {Hardware_Parameters} \
    CONFIG.Phase_Width {30} \
    CONFIG.Output_Width {16} \
    CONFIG.Phase_Increment {Programmable} \
    CONFIG.Output_Selection {Sine_and_Cosine} \
    CONFIG.Noise_Shaping {None} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Latency_Configuration {Configurable} \
    CONFIG.Latency {7}] [get_ips dds_phase_correction]

# DDS lookup-table latency is 7 enabled clocks.
create_ip -name dds_compiler -vendor xilinx.com -library ip -version 6.0 -module_name dds_lut_sin
set_property -dict [list \
    CONFIG.PartsPresent {SIN_COS_LUT_only} \
    CONFIG.Parameter_Entry {Hardware_Parameters} \
    CONFIG.Phase_Width {16} \
    CONFIG.Output_Width {16} \
    CONFIG.Output_Selection {Sine_and_Cosine} \
    CONFIG.Noise_Shaping {Taylor_Series_Corrected} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Latency_Configuration {Configurable} \
    CONFIG.Latency {7}] [get_ips dds_lut_sin]

# CORDIC latency depends on maximum pipelining for the selected device.
create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name cordic_arctan
set_property -dict [list \
    CONFIG.Functional_Selection {Arc_Tan} \
    CONFIG.Architectural_Configuration {Parallel} \
    CONFIG.Pipelining_Mode {Maximum} \
    CONFIG.Data_Format {SignedFraction} \
    CONFIG.Phase_Format {Scaled_Radians} \
    CONFIG.Input_Width {32} \
    CONFIG.Output_Width {32} \
    CONFIG.Round_Mode {Nearest_Even} \
    CONFIG.Coarse_Rotation {true} \
    CONFIG.Compensation_Scaling {No_Scale_Compensation} \
    CONFIG.flow_control {NonBlocking}] [get_ips cordic_arctan]

generate_target all [get_ips]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property top link11_slew_demod_top [get_filesets sources_1]
set_property top link11_slew_simulate [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created project: [file join $project_dir link11_slew.xpr]"
puts "Target part: $part_name"
