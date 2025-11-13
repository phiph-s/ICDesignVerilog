SRC_IP   := $(shell find ip/aes-verilog -name '*.v')
SRC_RTL  := $(shell find rtl -name '*.sv' -o -name '*.v')
SRC_TB   := $(shell find tb -name '*.sv' -o -name '*.v')

all: sim

sim:
	iverilog -g2012 -o sim.out $(SRC_IP) $(SRC_RTL) $(SRC_TB)
	vvp sim.out

clean:
	rm -f sim.out wave.vcd
