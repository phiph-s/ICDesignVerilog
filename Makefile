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

# AT25010 Interface sim
sim_at25010:
	iverilog -g2012 -o sim_at25010.out ip/spi-master/SPI_Master.v ip/spi-master/SPI_Master_With_Single_CS.v rtl/at25010_interface.v tb/tb_at25010_interface.v
	vvp sim_at25010.out

# MFRC522 Interface sim
sim_mfrc522:
	iverilog -g2012 -o sim_mfrc522.out ip/spi-master/SPI_Master.v ip/spi-master/SPI_Master_With_Single_CS.v rtl/mfrc522_interface.v tb/tb_mfrc522_interface.v
	vvp sim_mfrc522.out

# NFC Card Detector sim
sim_detector:
	iverilog -g2012 -o sim_detector.out rtl/nfc_card_detector.v tb/tb_nfc_card_detector.v
	vvp sim_detector.out

# Main Core (full integration) sim
sim_main:
	iverilog -g2012 -o sim_main.out $(SRC_IP) ip/spi-master/SPI_Master.v ip/spi-master/SPI_Master_With_Single_CS.v \
		rtl/aes_core.v rtl/nonce_generator.v rtl/at25010_interface.v rtl/mfrc522_interface.v \
		rtl/nfc_card_detector.v rtl/auth_controller.v rtl/main_core.v tb/tb_main_core.v
	vvp sim_main.out

clean:
	rm -f *.out *.vcd
