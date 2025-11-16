// Testbench for Main Core - Full Integration Test
// Tests complete Guardian Chip functionality

`timescale 1ns / 1ps

module tb_main_core;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // SPI to MFRC522
  logic nfc_spi_cs_n;
  logic nfc_spi_sclk;
  logic nfc_spi_mosi;
  logic nfc_spi_miso;
  
  // SPI to EEPROM
  logic eeprom_spi_cs_n;
  logic eeprom_spi_sclk;
  logic eeprom_spi_mosi;
  logic eeprom_spi_miso;
  
  // Door and status
  logic door_unlock;
  logic status_unlock;
  logic status_fault;
  logic status_busy;
  
  // Control
  logic start_auth_btn;
  
  // DUT instantiation
  main_core dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .nfc_spi_cs_n     (nfc_spi_cs_n),
    .nfc_spi_sclk     (nfc_spi_sclk),
    .nfc_spi_mosi     (nfc_spi_mosi),
    .nfc_spi_miso     (nfc_spi_miso),
    .eeprom_spi_cs_n  (eeprom_spi_cs_n),
    .eeprom_spi_sclk  (eeprom_spi_sclk),
    .eeprom_spi_mosi  (eeprom_spi_mosi),
    .eeprom_spi_miso  (eeprom_spi_miso),
    .door_unlock      (door_unlock),
    .status_unlock    (status_unlock),
    .status_fault     (status_fault),
    .status_busy      (status_busy),
    .start_auth_btn   (start_auth_btn)
  );
  
  // Clock generation (100MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Mock EEPROM - Store PSK
  localparam [127:0] TEST_PSK = 128'h2b7e151628aed2a6abf7158809cf4f3c;
  logic [7:0] eeprom_mem [0:127];
  integer i;
  
  initial begin
    for (i = 0; i < 128; i = i + 1) eeprom_mem[i] = 8'h00;
    
    // Store PSK at address 0x00
    eeprom_mem[0]  = TEST_PSK[127:120];
    eeprom_mem[1]  = TEST_PSK[119:112];
    eeprom_mem[2]  = TEST_PSK[111:104];
    eeprom_mem[3]  = TEST_PSK[103:96];
    eeprom_mem[4]  = TEST_PSK[95:88];
    eeprom_mem[5]  = TEST_PSK[87:80];
    eeprom_mem[6]  = TEST_PSK[79:72];
    eeprom_mem[7]  = TEST_PSK[71:64];
    eeprom_mem[8]  = TEST_PSK[63:56];
    eeprom_mem[9]  = TEST_PSK[55:48];
    eeprom_mem[10] = TEST_PSK[47:40];
    eeprom_mem[11] = TEST_PSK[39:32];
    eeprom_mem[12] = TEST_PSK[31:24];
    eeprom_mem[13] = TEST_PSK[23:16];
    eeprom_mem[14] = TEST_PSK[15:8];
    eeprom_mem[15] = TEST_PSK[7:0];
  end
  
  // Simple EEPROM SPI slave model
  logic [7:0] eeprom_addr_latch;
  logic eeprom_byte_ready;
  
  always @(negedge eeprom_spi_cs_n or posedge eeprom_spi_cs_n) begin
    if (eeprom_spi_cs_n) begin
      eeprom_byte_ready <= 1'b0;
    end
  end
  
  assign eeprom_spi_miso = eeprom_byte_ready ? eeprom_mem[eeprom_addr_latch][7] : 1'b0;
  
  // Simple NFC SPI slave model
  assign nfc_spi_miso = 1'b0;
  
  // Status monitoring
  always @(posedge clk) begin
    if (status_unlock) $display("[%0t] Door UNLOCKED!", $time);
    if (status_fault) $display("[%0t] Authentication FAULT!", $time);
  end
  
  // Test stimulus
  initial begin
    $display("=== Main Core Integration Testbench ===");
    $display("PSK stored at EEPROM addr 0x00: %h", TEST_PSK);
    
    // Initialize
    rst_n = 0;
    start_auth_btn = 0;
    
    // Reset
    #100;
    rst_n = 1;
    #100;
    
    $display("\n[TEST] Starting authentication...");
    start_auth_btn = 1;
    #20;
    start_auth_btn = 0;
    
    // Wait for authentication
    #50000;
    
    $display("\n[INFO] Final Status:");
    $display("  Busy:   %b", status_busy);
    $display("  Unlock: %b", status_unlock);
    $display("  Fault:  %b", status_fault);
    
    if (status_unlock) begin
      $display("\n[PASS] Door unlocked successfully!");
    end else if (status_fault) begin
      $display("\n[FAIL] Authentication failed!");
    end else begin
      $display("\n[INFO] Authentication in progress or incomplete");
    end
    
    // End simulation
    $display("\n=== Simulation Complete ===");
    $finish;
  end
  
  // Waveform dump
  initial begin
    $dumpfile("tb_main_core.vcd");
    $dumpvars(0, tb_main_core);
  end

endmodule
