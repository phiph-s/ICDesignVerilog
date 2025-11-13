SRC_IP   := $(shell find ip/aes-verilog -name '*.v')
SRC_RTL  := $(shell find rtl -name '*.sv' -o -name '*.v')
SRC_TB   := $(shell find tb -name '*.sv' -o -name '*.v')

# AES-only sim
sim_aes:
	iverilog -g2012 -o sim_aes.out $(SRC_IP) rtl/aes_core.v tb/tb_aes_core.v
	vvp sim_aes.out

# NONCE-only sim
sim_nonce:
	iverilog -g2012 -o sim_nonce.out rtl/nonce_generator.v tb/tb_nonce_generator.v
	vvp sim_nonce.out

# SPI-only sim
sim_spi:
	iverilog -g2012 -o sim_spi.out rtl/spi_master.sv tb/tb_spi_master.sv tb/spi_slave_dummy.v
	vvp sim_spi.out

# SPI-only sim
sim_at25010:
	iverilog -g2012 -o sim_at25010.out rtl/at25010_if.sv tb/tb_at25010_if.v rtl/spi_master.v
	vvp sim_at25010.out

clean:
	rm -f sim.out wave.vcd
