# ==============================================================================
# DE2_Organ.sdc  —  Synopsys Design Constraints (timing)
# ==============================================================================

# 50 MHz system clock (20 ns period)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# Derive PLL clocks (none used here — all clocks are divided from CLOCK_50)
derive_clock_uncertainty

# False path on asynchronous inputs (switches, buttons)
set_false_path -from [get_ports {SW[*]}]  -to [all_registers]
set_false_path -from [get_ports {KEY[*]}] -to [all_registers]

# False path on output LEDs and 7-segment
set_false_path -from [all_registers] -to [get_ports {LEDR[*]}]
set_false_path -from [all_registers] -to [get_ports {LEDG[*]}]
set_false_path -from [all_registers] -to [get_ports {HEX*}]

# Audio outputs — relax timing (audio runs at <<50 MHz)
set_false_path -from [all_registers] -to [get_ports {AUD_*}]
set_false_path -from [all_registers] -to [get_ports {I2C_*}]
