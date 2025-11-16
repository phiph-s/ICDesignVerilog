// Testbench for Main Core - Full Integration Test
// Tests complete Guardian Chip functionality with realistic SPI mocks

`timescale 1ns / 1ps
`define SIMULATION

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
  
  // Test parameters
  localparam [127:0] TEST_PSK = 128'h2b7e151628aed2a6abf7158809cf4f3c;
  localparam [127:0] WRONG_PSK = 128'hffffffffffffffffffffffffffffffff;
  localparam [63:0]  TEST_RC  = 64'h0123456789abcdef;
  
  // Test monitoring
  integer success_count = 0;
  integer fail_count = 0;
  logic card_has_wrong_key = 0;
  
  // DUT instantiation
  main_core #(
    .UNLOCK_DURATION_PARAM(32'd100000)  // 1ms for faster testing
  ) dut (
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
  
  // ============================================
  // EEPROM SPI Slave Mock (AT25010)
  // ============================================
  logic [7:0] eeprom_mem [0:127];
  logic [7:0] eeprom_shift_reg;
  logic [7:0] eeprom_cmd;
  logic [6:0] eeprom_addr;
  integer eeprom_bit_count;
  integer eeprom_state; // 0=idle, 1=cmd, 2=addr, 3=data
  logic eeprom_spi_cs_n_prev;
  
  initial begin
    integer i;
    for (i = 0; i < 128; i = i + 1) eeprom_mem[i] = 8'h00;
    
    eeprom_bit_count = 0;
    eeprom_state = 0;
    eeprom_shift_reg = 8'h00;
    eeprom_spi_cs_n_prev = 1'b1;
    
    $display("[EEPROM] Mock initialized");
  end
  
  // EEPROM always contains correct PSK (reader always has correct key)
  initial begin
    // Store correct PSK at address 0x00
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
    $display("[EEPROM] Loaded correct PSK");
  end
  
  // EEPROM SPI slave behavior - trigger on falling edge of SCLK
  always @(posedge clk) begin
    eeprom_spi_cs_n_prev <= eeprom_spi_cs_n;
    
    // CS rising edge resets state
    if (!eeprom_spi_cs_n_prev && eeprom_spi_cs_n) begin
      eeprom_bit_count <= 0;
      eeprom_state <= 0;
      eeprom_shift_reg <= 8'h00;
      // $display("[%0t] [EEPROM] CS deasserted, state reset", $time);
    end
  end
  
  // Shift on SCLK rising edge
  always @(posedge eeprom_spi_sclk) begin
    if (!eeprom_spi_cs_n) begin
      // Shift in MOSI
      eeprom_shift_reg <= {eeprom_shift_reg[6:0], eeprom_spi_mosi};
      eeprom_bit_count <= eeprom_bit_count + 1;
      
      if (eeprom_bit_count == 7) begin
        case (eeprom_state)
          0: begin // Command byte
            eeprom_cmd <= {eeprom_shift_reg[6:0], eeprom_spi_mosi};
            // $display("[%0t] [EEPROM] CMD: 0x%02h", $time, {eeprom_shift_reg[6:0], eeprom_spi_mosi});
            if ({eeprom_shift_reg[6:0], eeprom_spi_mosi} == 8'h03) begin // READ
              eeprom_state <= 2; // Next: address (skip state 1)
            end
            eeprom_bit_count <= 0;
          end
          2: begin // Address byte
            eeprom_addr <= {eeprom_shift_reg[5:0], eeprom_spi_mosi};
            eeprom_state <= 3; // Next: data
            // Pre-load first data byte
            eeprom_shift_reg <= eeprom_mem[{eeprom_shift_reg[5:0], eeprom_spi_mosi}];
            // $display("[%0t] [EEPROM] ADDR: 0x%02h, Data: 0x%02h", $time, {eeprom_shift_reg[5:0], eeprom_spi_mosi}, eeprom_mem[{eeprom_shift_reg[5:0], eeprom_spi_mosi}]);
            eeprom_bit_count <= 0;
          end
          3: begin // Data bytes
            eeprom_addr <= eeprom_addr + 1;
            if (eeprom_addr + 1 < 128) begin
              eeprom_shift_reg <= eeprom_mem[eeprom_addr + 1];
            end else begin
              eeprom_shift_reg <= 8'hFF;
            end
            eeprom_bit_count <= 0;
          end
        endcase
      end
    end
  end
  
  // Output shift register MSB on MISO
  assign eeprom_spi_miso = (!eeprom_spi_cs_n && eeprom_state == 3) ? eeprom_shift_reg[7] : 1'b0;
  
  // ============================================
  // NFC SPI Slave Mock (MFRC522 with Card)
  // ============================================
  logic [7:0] nfc_shift_reg;
  logic [7:0] nfc_addr;
  logic [7:0] nfc_data;
  logic nfc_is_write;
  integer nfc_bit_count;
  integer nfc_cmd_count;
  integer nfc_write_count;  // Count WRITE commands (0=AUTH_INIT, 1=AUTH_RESPONSE)
  logic [127:0] card_encrypted_challenge;
  logic [127:0] card_encrypted_response;
  logic [7:0] nfc_response_bytes [0:15];
  logic card_auth_failed;
  logic auth_response_received;  // Track if AUTH response was received
  
  // AES core for card to encrypt challenge with real AES
  logic card_aes_start;
  logic card_aes_done;
  logic [127:0] card_aes_key;
  logic [127:0] card_aes_plaintext;
  logic [127:0] card_aes_ciphertext;
  
  aes_core card_aes (
    .clk(clk),
    .rst_n(rst_n),
    .start(card_aes_start),
    .mode(1'b0),  // Encrypt (0=encrypt, 1=decrypt)
    .key(card_aes_key),
    .block_in(card_aes_plaintext),
    .block_out(card_aes_ciphertext),
    .done(card_aes_done)
  );
  
  initial begin
    nfc_cmd_count = 0;
    nfc_write_count = 0;
    auth_response_received = 0;
    card_aes_start = 0;
    card_aes_key = TEST_PSK;  // Start with correct key
    card_aes_plaintext = {TEST_RC, 64'h0};
    
    // Wait for reset and then encrypt initial challenge
    @(posedge rst_n);
    #100;
    card_aes_start = 1'b1;
  end
  
  // Card encrypts challenge with correct or wrong key based on test
  // Trigger card encryption when key changes
  always @(card_has_wrong_key) begin
    if (card_has_wrong_key) begin
      card_aes_key = WRONG_PSK;
    end else begin
      card_aes_key = TEST_PSK;
    end
    card_aes_plaintext = {TEST_RC, 64'h0};
    #100;
    card_aes_start = 1'b1;
  end
  
  // Wait for AES encryption to complete and capture result
  always @(posedge clk) begin
    if (card_aes_start) begin
      card_aes_start <= 1'b0;
    end
    if (card_aes_done) begin
      card_encrypted_challenge <= card_aes_ciphertext;
      $display("[%0t] [CARD] Challenge ready: %h", $time, card_aes_ciphertext);
    end
  end
  
  // NFC SPI slave behavior - simulates MFRC522 reading from real card
  // Simplified: If card_auth_failed, return 0xFF for everything except initial challenge
  always @(posedge nfc_spi_sclk or posedge nfc_spi_cs_n) begin
    if (nfc_spi_cs_n) begin
      nfc_bit_count <= 0;
      nfc_shift_reg <= 8'h00;
    end else begin
      nfc_shift_reg <= {nfc_shift_reg[6:0], nfc_spi_mosi};
      nfc_bit_count <= nfc_bit_count + 1;
      
      if (nfc_bit_count == 7) begin
        // First byte: address/command  (use current byte with MOSI bit)
        nfc_is_write <= nfc_shift_reg[6];  // Bit 7 of the completed byte
        nfc_addr <= {nfc_shift_reg[5:0], nfc_spi_mosi, 1'b0};
        
        // Reset byte counter on new write command (new transaction)
        if (nfc_shift_reg[6]) begin  // Bit 7 = write flag (shifted position)
          nfc_cmd_count <= 0;
          nfc_write_count <= nfc_write_count + 1;
          if (nfc_write_count == 0)
            $display("[%0t] [CARD] ← AUTH_INIT", $time);
          else if (nfc_write_count == 1)
            $display("[%0t] [CARD] ← AUTH", $time);
        end else begin
          // READ: Pre-load data for second byte transmission
          if (nfc_write_count == 0) begin
            // Before any WRITE (shouldn't happen): Return 0
            nfc_shift_reg <= 8'h00;
          end else if (nfc_write_count == 1) begin
            // After AUTH_INIT, before AUTH response: Return encrypted challenge
            nfc_shift_reg <= card_encrypted_challenge[(127 - nfc_cmd_count*8) -: 8];
            if (nfc_cmd_count == 0)
              $display("[%0t] [CARD] → Encrypted challenge", $time);
          end else if (card_auth_failed) begin
            // After AUTH response, if auth failed: Return 0xFF for everything
            nfc_shift_reg <= 8'hFF;
          end else begin
            // After AUTH response, if auth OK: Return status (0x00) then encrypted ID (0x42)
            nfc_shift_reg <= (nfc_cmd_count == 0) ? 8'h00 : 8'h42;
            if (nfc_cmd_count == 0)
              $display("[%0t] [CARD] ← GET_ID → Encrypted ID", $time);
          end
        end
      end else if (nfc_bit_count == 15) begin
        // Second byte: data
        if (nfc_is_write) begin
          // WRITE received
          if (nfc_write_count >= 2) begin
            // Second+ WRITE: AUTH response received
            auth_response_received <= 1;
          end
        end else begin
          // Reading from card - increment counter after read completes
          nfc_cmd_count <= nfc_cmd_count + 1;
        end
      end
    end
  end
  
  assign nfc_spi_miso = nfc_shift_reg[7];
  
  // Status monitoring with edge detection
  logic status_unlock_prev, status_fault_prev;
  logic auth_completed_flag;
  
  always @(posedge clk) begin
    status_unlock_prev <= status_unlock;
    status_fault_prev <= status_fault;
    
    // Detect rising edge of unlock
    if (status_unlock && !status_unlock_prev) begin
      success_count = success_count + 1;
      auth_completed_flag = 1;
      $display("[%0t] ✓ Door UNLOCKED! (Success #%0d)", $time, success_count);
    end
    

    
    // Detect rising edge of fault
    if (status_fault && !status_fault_prev) begin
      fail_count = fail_count + 1;
      auth_completed_flag = 1;
      $display("[%0t] ✗ Authentication REJECTED! (Rejection #%0d)", $time, fail_count);
    end
  end
  
    // Internal state monitoring (milestone events only)
  logic [4:0] last_auth_state;
  logic auth_result_shown;
  initial begin
    last_auth_state = 0;
    auth_result_shown = 0;
  end
  
  always @(posedge clk) begin
    // Auth state transitions (key milestones only)
    if (dut.u_auth_controller.state != last_auth_state) begin
      case (dut.u_auth_controller.state)
        // Removed redundant prints - using chip's detailed prints instead
        dut.u_auth_controller.ST_SUCCESS: begin
          if (!auth_result_shown) begin
            $display("[%0t] ✓ Card authenticated successfully!", $time);
            auth_result_shown = 1;
          end
        end
        dut.u_auth_controller.ST_FAILED: begin
          if (!auth_result_shown) begin
            $display("[%0t] ✗ Authentication rejected!", $time);
            auth_result_shown = 1;
          end
        end
        dut.u_auth_controller.ST_IDLE: auth_result_shown = 0; // Reset for next auth
      endcase
      last_auth_state = dut.u_auth_controller.state;
    end
  end
  
  // Test stimulus
  initial begin
    $display("\n=== Guardian Chip - Main Core Integration Test ===");
    $display("Correct PSK: %h", TEST_PSK);
    $display("Wrong PSK:   %h", WRONG_PSK);
    $display("");
    
    // Initialize
    rst_n = 0;
    start_auth_btn = 0;
    card_has_wrong_key = 0;
    
    // Reset
    #200;
    rst_n = 1;
    #200;
    
    // ========================================
    // TEST 1: Successful authentication
    // ========================================
    $display("[TEST 1] Authentication with CORRECT key (card has correct key)...");
    card_has_wrong_key = 0;
    nfc_cmd_count = 0;  // Reset NFC mock counter
    nfc_write_count = 0;  // Reset WRITE counter
    #100;
    
    auth_completed_flag = 0;
    start_auth_btn = 1;
    #100;
    start_auth_btn = 0;
    
    // Wait for authentication to complete
    fork
      begin
        wait(auth_completed_flag);
        #1000;
      end
      begin
        #30000000; // 30ms timeout
        $display("[WARNING] Test 1 timeout");
      end
    join_any
    disable fork;
    
    #5000;
    
    if (success_count >= 1) begin
      $display("[PASS] Test 1: Door unlocked successfully!\n");
    end else if (fail_count >= 1) begin
      $display("[FAIL] Test 1: Authentication was rejected!\n");
    end else begin
      $display("[FAIL] Test 1: No response from system\n");
    end
    
    // Wait for unlock timer to expire (1ms in simulation)
    #2000000;  // 2ms wait to ensure timer expired
    
    // ========================================
    // TEST 2: Failed authentication (card has wrong key)
    // ========================================
    $display("[TEST 2] Card with WRONG key (reader should reject)...");
    card_has_wrong_key = 1;
    nfc_cmd_count = 0;  // Reset NFC mock counter
    nfc_write_count = 0;  // Reset WRITE counter
    #100;
    
    auth_completed_flag = 0;
    start_auth_btn = 1;
    #100;
    start_auth_btn = 0;
    
    fork
      begin
        wait(auth_completed_flag);
        #1000;
      end
      begin
        #30000000; // 30ms timeout
        $display("[WARNING] Test 2 timeout");
      end
    join_any
    disable fork;
    
    #5000;
    
    if (fail_count >= 1) begin
      $display("[PASS] Test 2: Card with wrong key correctly rejected!\n");
    end else if (success_count >= 2) begin
      $display("[FAIL] Test 2: Reader should have rejected card with wrong key!\n");
    end else begin
      $display("[FAIL] Test 2: No response from system\n");
    end
    
    // Wait before next test
    #2000000;  // 2ms wait
    
    // ========================================
    // TEST 3: Recovery after failed auth
    // ========================================
    $display("[TEST 3] Recovery - Card with CORRECT key again...");
    card_has_wrong_key = 0;
    nfc_cmd_count = 0;  // Reset NFC mock counter
    nfc_write_count = 0;  // Reset WRITE counter
    #100;
    
    auth_completed_flag = 0;
    start_auth_btn = 1;
    #100;
    start_auth_btn = 0;
    
    fork
      begin
        wait(auth_completed_flag);
        #1000;
      end
      begin
        #30000000; // 30ms timeout
        $display("[WARNING] Test 3 timeout");
      end
    join_any
    disable fork;
    
    #5000;
    
    if (success_count >= 2) begin
      $display("[PASS] Test 3: System recovered, door unlocked!\n");
    end else if (fail_count >= 2) begin
      $display("[FAIL] Test 3: Authentication failed!\n");
    end else begin
      $display("[FAIL] Test 3: No response from system\n");
    end
    
    // Summary
    #5000;
    $display("=== Test Results ===");
    $display("Successful authentications: %0d", success_count);
    $display("Rejected authentications:   %0d", fail_count);
    
    if (success_count == 2 && fail_count == 1) begin
      $display("\n✓✓✓ ALL TESTS PASSED ✓✓✓");
    end else begin
      $display("\n✗✗✗ TESTS FAILED ✗✗✗");
      $display("Expected: 2 successes, 1 rejection");
      $display("Got:      %0d successes, %0d rejections", success_count, fail_count);
    end
    
    $display("");
    $finish;
  end
  
  // Waveform dump
  initial begin
    $dumpfile("tb_main_core.vcd");
    $dumpvars(0, tb_main_core);
  end

endmodule
