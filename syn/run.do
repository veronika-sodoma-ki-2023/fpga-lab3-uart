# Синтез UART (варіант 22) у Siemens Precision
# Цільова ПЛІС: Xilinx Artix-7 XC7A35T (плата Basys 3), тактова частота 50 МГц

new_project -name uart_lab -folder . -createimpl_name uart_impl

setup_design -manufacturer Xilinx -family ARTIX-7 -part 7A35TCPG236 -speed 1
setup_design -frequency 50

add_input_file design.sv

compile
synthesize

report_area
report_timing
