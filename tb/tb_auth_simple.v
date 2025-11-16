// Simplified testbench for debugging auth_controller key loading

`timescale 1ns / 1ps

module tb_auth_simple;

  logic clk, rst_n;
  logic start_auth;
  logic         key_load_req;
  logic [6:0]   key_addr;
  logic [7:0]   key_data;
  logic         key_data_valid;
  
  // Dummy signals
  logic         auth_success, auth_failed, auth_busy;
  logic [127:0] card_id;
  logic         card_id_valid;
  logic         aes_start, aes_mode, aes_done;
  logic [127:0] aes_key, aes_block_in, aes_block_out;
  logic         nonce_req, nonce_valid;
  logic [63:0]  nonce;
  logic         nfc_cmd_valid, nfc_cmd_ready, nfc_cmd_write, nfc_cmd_done;
  logic [5:0]   nfc_cmd_addr;
  logic [7:0]   nfc_cmd_wdata, nfc_cmd_rdata;
  logic         timeout_start, timeout_occurred;
  
  // Test PSK
  localparam [127:0] TEST_PSK = 128'h2b7e151628aed2a6abf7158809cf4f3c;
  logic [7:0] eeprom_mem [0:15];
  
  initial begin
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
  
  // DUT
  auth_controller dut (.*);
  
  // Clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // EEPROM mock - immediate response
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      key_data <= 8'h0;
      key_data_valid <= 1'b0;
    end else begin
      if (key_load_req) begin
        key_data <= eeprom_mem[key_addr];
        key_data_valid <= 1'b1;
        $display("  [EEPROM] addr=%0d, data=%02h", key_addr, eeprom_mem[key_addr]);
      end else begin
        key_data_valid <= 1'b0;
      end
    end
  end
  
  // Dummy AES (immediate)
  assign aes_done = aes_start;
  assign aes_block_out = aes_block_in ^ aes_key;
  
  // Dummy Nonce
  assign nonce_valid = nonce_req;
  assign nonce = 64'hfedcba9876543210;
  
  // Dummy NFC
  assign nfc_cmd_ready = 1'b1;
  assign nfc_cmd_done = nfc_cmd_valid;
  assign nfc_cmd_rdata = 8'hAA;
  
  // No timeout
  assign timeout_occurred = 1'b0;
  
  // Monitor state changes
  logic [4:0] prev_state;
  always @(posedge clk) begin
    if (dut.state != prev_state) begin
      $display("[%0t] State: %0d -> %0d", $time, prev_state, dut.state);
      prev_state <= dut.state;
    end
  end
  
  // Monitor auth signals
  always @(posedge clk) begin
    if (auth_success) $display("[%0t] *** AUTH SUCCESS ***", $time);
    if (auth_failed) $display("[%0t] *** AUTH FAILED ***", $time);
  end
  
  // Test
  initial begin
    $display("=== Simple Auth Test ===");
    rst_n = 0;
    start_auth = 0;
    #20;
    rst_n = 1;
    #20;
    
    $display("\n[TEST] Start authentication");
    start_auth = 1;
    #10;
    start_auth = 0;
    
    #5000;
    
    if (auth_success) $display("[PASS] Auth succeeded!");
    else if (auth_failed) $display("[FAIL] Auth failed!");
    else $display("[INFO] Auth still busy...");
    
    $finish;
  end

endmodule
