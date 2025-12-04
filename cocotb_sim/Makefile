# Makefile

# Defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Common sources
SPI_MASTER_SRC = $(PWD)/../ip/spi-master/SPI_Master_With_Single_CS.v $(PWD)/../ip/spi-master/SPI_Master.v

# AT25010 Test
at25010:
	$(MAKE) sim MODULE=test_at25010 TOPLEVEL=at25010_interface VERILOG_SOURCES="$(PWD)/../rtl/at25010_interface.v $(SPI_MASTER_SRC)"

# MFRC522 Test
mfrc522:
	$(MAKE) sim MODULE=test_mfrc522 TOPLEVEL=mfrc522_interface VERILOG_SOURCES="$(PWD)/../rtl/mfrc522_interface.v $(SPI_MASTER_SRC)"

include $(shell cocotb-config --makefiles)/Makefile.sim
