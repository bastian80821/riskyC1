# build.tcl - regenerate the Vivado project from source.
# Usage (from the repo root, in the Vivado Tcl console):
#   cd <path-to-repo>
#   source scripts/build.tcl
#
# This replaces committing the Vivado project: it recreates the project,
# adds the RTL and constraints, and targets the correct part.

set proj_name "riscyC1"
set part      "xc7s50csga324-1"

# Create the project in a build/ dir (which is gitignored)
create_project $proj_name ./build -part $part -force

# Add all SystemVerilog source
add_files -fileset sources_1 [glob ./rtl/*.sv]
set_property file_type SystemVerilog [get_files ./rtl/*.sv]

# Add testbenches if any exist yet
if {[llength [glob -nocomplain ./tb/*.sv]] > 0} {
    add_files -fileset sim_1 [glob ./tb/*.sv]
    set_property file_type SystemVerilog [get_files ./tb/*.sv]
}

# Add the minimal project constraints
add_files -fileset constrs_1 [glob ./constraints/*.xdc]

# Set the top module (change as the design grows)
set_property top blink [current_fileset]

puts "Project '$proj_name' created for part $part."
puts "Next: launch_runs synth_1, then impl_1, then write_bitstream — or use the GUI."
