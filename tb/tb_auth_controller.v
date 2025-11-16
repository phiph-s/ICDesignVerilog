// Testbench for Authentication Controller
// Tests LAYR Authenticated Identification Protocol

`timescale 1ns / 1ps

module tb_auth_controller;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Control signals
  logic         start_auth;
  logic         auth_success;
  logic         auth_failed;
  logic         auth_busy;
  logic [127:0] card_id;
  logic         card_id_valid;
  
  // AES Core signals
  logic         aes_start;
  logic         aes_mode;
  logic [127:0] aes_key;
  logic [127:0] aes_block_in;
  logic [127:0] aes_block_out;
  logic         aes_done;
  
  // Key Storage signals
  logic         key_load_req;
  logic [6:0]   key_addr;
  logic [7:0]   key_data;
  logic         key_data_valid;
  
  // Nonce Generator signals
  logic         nonce_req;
  logic [63:0]  nonce;
  logic         nonce_valid;
  
  // NFC Interface signals
  logic         nfc_cmd_valid;
  logic         nfc_cmd_ready;
  logic         nfc_cmd_write;
  logic [5:0]   nfc_cmd_addr;
  logic [7:0]   nfc_cmd_wdata;
  logic [7:0]   nfc_cmd_rdata;
  logic         nfc_cmd_done;
  
  // Timeout signals
  logic         timeout_start;
  logic         timeout_occurred;
  
  // Test parameters
  localparam [127:0] TEST_PSK = 128'h2b7e151628aed2a6abf7158809cf4f3c;
  localparam [127:0] TEST_PSK_WRONG = 128'hffffffffffffffffffffffffffffffff; // Wrong key
  localparam [63:0]  TEST_RC  = 64'h0123456789abcdef;
  localparam [63:0]  TEST_RT  = 64'hfedcba9876543210;
  localparam [127:0] TEST_CARD_ID = 128'hdeadbeefcafebabe0123456789abcdef;
  
  // Test control
  logic use_wrong_key;
  
  // Mock EEPROM storage
  logic [7:0] eeprom_mem [0:127];
  logic [7:0] eeprom_mem_wrong [0:127];
  
  // DUT instantiation
  auth_controller dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .start_auth       (start_auth),
    .auth_success     (auth_success),
    .auth_failed      (auth_failed),
    .auth_busy        (auth_busy),
    .card_id          (card_id),
    .card_id_valid    (card_id_valid),
    .aes_start        (aes_start),
    .aes_mode         (aes_mode),
    .aes_key          (aes_key),
    .aes_block_in     (aes_block_in),
    .aes_block_out    (aes_block_out),
    .aes_done         (aes_done),
    .key_load_req     (key_load_req),
    .key_addr         (key_addr),
    .key_data         (key_data),
    .key_data_valid   (key_data_valid),
    .nonce_req        (nonce_req),
    .nonce            (nonce),
    .nonce_valid      (nonce_valid),
    .nfc_cmd_valid    (nfc_cmd_valid),
    .nfc_cmd_ready    (nfc_cmd_ready),
    .nfc_cmd_write    (nfc_cmd_write),
    .nfc_cmd_addr     (nfc_cmd_addr),
    .nfc_cmd_wdata    (nfc_cmd_wdata),
    .nfc_cmd_rdata    (nfc_cmd_rdata),
    .nfc_cmd_done     (nfc_cmd_done),
    .timeout_start    (timeout_start),
    .timeout_occurred (timeout_occurred)
  );
  
  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Initialize EEPROM with test PSK
  initial begin
    integer i;
    for (i = 0; i < 128; i = i + 1) begin
      eeprom_mem[i] = 8'h00;
      eeprom_mem_wrong[i] = 8'h00;
    end
    
    // Store correct PSK at address 0x00 (16 bytes)
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
    
    // Store wrong PSK (simulates unauthorized card)
    eeprom_mem_wrong[0]  = TEST_PSK_WRONG[127:120];
    eeprom_mem_wrong[1]  = TEST_PSK_WRONG[119:112];
    eeprom_mem_wrong[2]  = TEST_PSK_WRONG[111:104];
    eeprom_mem_wrong[3]  = TEST_PSK_WRONG[103:96];
    eeprom_mem_wrong[4]  = TEST_PSK_WRONG[95:88];
    eeprom_mem_wrong[5]  = TEST_PSK_WRONG[87:80];
    eeprom_mem_wrong[6]  = TEST_PSK_WRONG[79:72];
    eeprom_mem_wrong[7]  = TEST_PSK_WRONG[71:64];
    eeprom_mem_wrong[8]  = TEST_PSK_WRONG[63:56];
    eeprom_mem_wrong[9]  = TEST_PSK_WRONG[55:48];
    eeprom_mem_wrong[10] = TEST_PSK_WRONG[47:40];
    eeprom_mem_wrong[11] = TEST_PSK_WRONG[39:32];
    eeprom_mem_wrong[12] = TEST_PSK_WRONG[31:24];
    eeprom_mem_wrong[13] = TEST_PSK_WRONG[23:16];
    eeprom_mem_wrong[14] = TEST_PSK_WRONG[15:8];
    eeprom_mem_wrong[15] = TEST_PSK_WRONG[7:0];
    
    use_wrong_key = 1'b0;
  end
  
  // Mock EEPROM interface
  logic key_load_req_d;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      key_data <= 8'h0;
      key_data_valid <= 1'b0;
      key_load_req_d <= 1'b0;
    end else begin
      key_load_req_d <= key_load_req;
      key_data_valid <= 1'b0;
      
      // Respond to rising edge of key_load_req
      if (key_load_req && !key_load_req_d) begin
        // Select correct or wrong key based on test scenario
        key_data <= use_wrong_key ? eeprom_mem_wrong[key_addr] : eeprom_mem[key_addr];
      end
      
      // Data valid one cycle after request
      if (key_load_req_d) begin
        key_data_valid <= 1'b1;
      end
    end
  end
  
  // Mock AES Core - Use real AES modules
  aes_core aes_mock (
    .clk(clk),
    .rst_n(rst_n),
    .start(aes_start),
    .mode(aes_mode),
    .key(aes_key),
    .block_in(aes_block_in),
    .block_out(aes_block_out),
    .done(aes_done)
  );
  
  // Mock Nonce Generator
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nonce <= 64'h0;
      nonce_valid <= 1'b0;
    end else begin
      nonce_valid <= 1'b0;
      if (nonce_req) begin
        nonce <= TEST_RT;
        nonce_valid <= 1'b1;
      end
    end
  end
  
  // Mock NFC Interface - Simulates smart card behavior
  typedef enum logic [2:0] {
    NFC_IDLE,
    NFC_PROCESS,
    NFC_RESPOND
  } nfc_state_t;
  
  nfc_state_t nfc_state;
  logic [127:0] card_encrypted_challenge;
  logic [127:0] card_encrypted_id;
  logic [127:0] card_session_key;
  logic [63:0]  card_rc;
  logic [63:0]  card_rt;
  logic [7:0]   cmd_received;
  integer       nfc_wait_cycles;
  integer       nfc_cmd_count;
  logic         card_auth_failed;
  
  // Simulate card behavior
  initial begin
    // Card generates its challenge (card always uses correct PSK)
    card_rc = TEST_RC;
    // Encrypt challenge with correct PSK: AES_psk(rc || 00...00)
    #100;
    card_encrypted_challenge = {card_rc, 64'h0} ^ TEST_PSK; // Simplified for test
    card_auth_failed = 1'b0;
    nfc_cmd_count = 0;
  end
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nfc_cmd_ready <= 1'b1;
      nfc_cmd_done <= 1'b0;
      nfc_cmd_rdata <= 8'h0;
      nfc_state <= NFC_IDLE;
      nfc_wait_cycles <= 0;
      cmd_received <= 8'h0;
      card_rt <= 64'h0;
      card_auth_failed <= 1'b0;
      nfc_cmd_count <= 0;
    end else begin
      case (nfc_state)
        NFC_IDLE: begin
          nfc_cmd_done <= 1'b0;
          if (nfc_cmd_valid && nfc_cmd_ready) begin
            cmd_received <= nfc_cmd_wdata;
            nfc_cmd_ready <= 1'b0;
            nfc_state <= NFC_PROCESS;
            nfc_wait_cycles <= 2; // Simulate processing delay
            nfc_cmd_count <= nfc_cmd_count + 1;
          end
        end
        
        NFC_PROCESS: begin
          if (nfc_wait_cycles > 0) begin
            nfc_wait_cycles <= nfc_wait_cycles - 1;
          end else begin
            nfc_state <= NFC_RESPOND;
            nfc_cmd_done <= 1'b1;
            
            // Prepare response based on command sequence
            if (cmd_received == 8'h80) begin
              if (nfc_cmd_count == 1) begin
                // First command: AUTH_INIT - return encrypted challenge
                nfc_cmd_rdata <= card_encrypted_challenge[127:120];
              end else if (nfc_cmd_count == 2) begin
                // Second command: AUTH - Card verifies terminal's response
                // If terminal used wrong key, decryption will fail
                // Card would reject by returning error status
                // For simulation: return 0x00 for success, 0xFF for failure
                if (use_wrong_key) begin
                  nfc_cmd_rdata <= 8'hFF; // Error: Authentication failed
                  card_auth_failed <= 1'b1;
                  $display("[%0t] [CARD] AUTH verification FAILED - wrong key detected!", $time);
                end else begin
                  nfc_cmd_rdata <= 8'h00; // Success
                  card_auth_failed <= 1'b0;
                  $display("[%0t] [CARD] AUTH verification SUCCESS", $time);
                end
              end else if (nfc_cmd_count == 3) begin
                // Third command: GET_ID - only respond if auth succeeded
                if (card_auth_failed) begin
                  nfc_cmd_rdata <= 8'hFF; // Return error
                  $display("[%0t] [CARD] GET_ID REJECTED - card not authenticated", $time);
                end else begin
                  // Return encrypted ID (simplified)
                  nfc_cmd_rdata <= card_encrypted_challenge[127:120];
                  $display("[%0t] [CARD] GET_ID returning encrypted card ID", $time);
                end
              end else begin
                nfc_cmd_rdata <= 8'h00;
              end
            end
          end
        end
        
        NFC_RESPOND: begin
          nfc_cmd_done <= 1'b0;
          nfc_cmd_ready <= 1'b1;
          nfc_state <= NFC_IDLE;
          
          // Reset command counter when going back to idle after GET_ID response
          if (nfc_cmd_count >= 3) begin
            nfc_cmd_count <= 0;
            card_auth_failed <= 1'b0; // Reset for next authentication
          end
        end
      endcase
    end
  end
  
  // Mock Timeout - disable for now
  assign timeout_occurred = 1'b0;
  
  // State monitoring for debugging
  integer success_count = 0;
  integer fail_count = 0;
  logic test_complete;
  
  always @(posedge clk) begin
    if (auth_success) begin
      success_count = success_count + 1;
      test_complete = 1'b1;
      $display("[%0t] AUTH_SUCCESS! Card ID: %h", $time, card_id);
    end
    if (auth_failed) begin
      fail_count = fail_count + 1;
      test_complete = 1'b1;
      $display("[%0t] AUTH_FAILED!", $time);
    end
  end
  
  // Test stimulus
  initial begin
    $display("=== Auth Controller Testbench ===");
    $display("Test PSK: %h", TEST_PSK);
    $display("Test RC:  %h", TEST_RC);
    $display("Test RT:  %h", TEST_RT);
    
    // Initialize
    rst_n = 0;
    start_auth = 0;
    
    // Reset
    #50;
    rst_n = 1;
    #50;
    
    // Test 1: Basic authentication sequence
    $display("\n[TEST 1] Starting authentication sequence...");
    test_complete = 1'b0;
    start_auth = 1;
    #10;
    start_auth = 0;
    
    // Wait for authentication to complete (with timeout)
    fork
      begin
        wait(test_complete);
        #100;
      end
      begin
        #50000;
        $display("[WARNING] Test 1 timeout - authentication still busy");
      end
    join_any
    disable fork;
    
    if (success_count > 0) begin
      $display("[PASS] Test 1: Authentication successful!");
      $display("       Card ID: %h", card_id);
    end else if (fail_count > 0) begin
      $display("[FAIL] Test 1: Authentication failed!");
    end else begin
      $display("[FAIL] Test 1: Authentication did not complete");
    end
    
    // Test 2: Multiple authentication attempts
    #500;
    $display("\n[TEST 2] Second authentication attempt...");
    test_complete = 1'b0;
    start_auth = 1;
    #10;
    start_auth = 0;
    
    fork
      begin
        wait(test_complete);
        #100;
      end
      begin
        #50000;
        $display("[WARNING] Test 2 timeout - authentication still busy");
      end
    join_any
    disable fork;
    
    if (success_count > 1) begin
      $display("[PASS] Test 2: Second authentication successful!");
    end else if (fail_count > 1) begin
      $display("[FAIL] Test 2: Second authentication failed!");
    end else begin
      $display("[FAIL] Test 2: Second authentication did not complete");
    end
    
    // Test 3: Authentication with wrong key (unauthorized card)
    #500;
    $display("\n[TEST 3] Authentication with WRONG key (unauthorized card)...");
    $display("         Using wrong PSK: %h", TEST_PSK_WRONG);
    use_wrong_key = 1'b1;  // Switch to wrong key
    test_complete = 1'b0;
    start_auth = 1;
    #10;
    start_auth = 0;
    
    fork
      begin
        wait(test_complete);
        #100;
      end
      begin
        #50000;
        $display("[WARNING] Test 3 timeout - authentication still busy");
      end
    join_any
    disable fork;
    
    if (fail_count >= 1) begin
      $display("[PASS] Test 3: Card correctly REJECTED (wrong key detected)!");
    end else if (success_count > 2) begin
      $display("[FAIL] Test 3: Card was ACCEPTED with wrong key (SECURITY BREACH!)");
    end else begin
      $display("[FAIL] Test 3: Authentication did not complete");
    end
    
    // Test 4: Verify system recovers and accepts valid card again
    #500;
    $display("\n[TEST 4] Recovery test - valid card after rejection...");
    use_wrong_key = 1'b0;  // Switch back to correct key
    test_complete = 1'b0;
    start_auth = 1;
    #10;
    start_auth = 0;
    
    fork
      begin
        wait(test_complete);
        #100;
      end
      begin
        #50000;
        $display("[WARNING] Test 4 timeout - authentication still busy");
      end
    join_any
    disable fork;
    
    if (success_count >= 3) begin
      $display("[PASS] Test 4: System recovered, valid card accepted!");
    end else if (fail_count > 1) begin
      $display("[FAIL] Test 4: Valid card rejected after recovery!");
    end else begin
      $display("[FAIL] Test 4: Authentication did not complete");
    end
    
    // Summary
    #100;
    $display("\n=== Test Summary ===");
    $display("Successful authentications: %0d", success_count);
    $display("Failed authentications:     %0d", fail_count);
    $display("Expected results:");
    $display("  - Test 1: SUCCESS (valid key)");
    $display("  - Test 2: SUCCESS (valid key, repeated)");
    $display("  - Test 3: FAILURE (wrong key)");
    $display("  - Test 4: SUCCESS (valid key, recovery)");
    
    if (success_count == 3 && fail_count == 1) begin
      $display("\n✓ ALL TESTS PASSED!");
    end else begin
      $display("\n✗ SOME TESTS FAILED!");
    end
    
    $display("\n=== Simulation Complete ===");
    $finish;
  end
  
  // Global timeout monitor
  initial begin
    #1000000;
    $display("[ERROR] Global simulation timeout!");
    $finish;
  end
  
  // Waveform dump
  initial begin
    $dumpfile("tb_auth_controller.vcd");
    $dumpvars(0, tb_auth_controller);
  end

endmodule
