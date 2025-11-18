// Testbench for NFC Card Detector
// Tests ISO14443A card detection and selection flow

`timescale 1ns/1ps

module tb_nfc_card_detector;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // DUT signals
  logic nfc_irq;
  logic card_detected;
  logic [31:0] card_uid;
  logic card_ready;
  logic start_auth;
  
  // NFC interface
  logic nfc_cmd_valid;
  logic nfc_cmd_ready;
  logic nfc_cmd_write;
  logic [5:0] nfc_cmd_addr;
  logic [7:0] nfc_cmd_wdata;
  logic [7:0] nfc_cmd_rdata;
  logic nfc_cmd_done;
  
  // Status
  logic detection_error;
  logic [7:0] error_code;
  
  // Clock generation (100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // DUT instantiation
  nfc_card_detector dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .nfc_irq          (nfc_irq),
    .card_detected    (card_detected),
    .card_uid         (card_uid),
    .card_ready       (card_ready),
    .start_auth       (start_auth),
    .nfc_cmd_valid    (nfc_cmd_valid),
    .nfc_cmd_ready    (nfc_cmd_ready),
    .nfc_cmd_write    (nfc_cmd_write),
    .nfc_cmd_addr     (nfc_cmd_addr),
    .nfc_cmd_wdata    (nfc_cmd_wdata),
    .nfc_cmd_rdata    (nfc_cmd_rdata),
    .nfc_cmd_done     (nfc_cmd_done),
    .detection_error  (detection_error),
    .error_code       (error_code)
  );
  
  // NFC Mock (simulates MFRC522 + Card responses)
  typedef enum {
    MOCK_IDLE,
    MOCK_REQA,
    MOCK_ANTICOLL,
    MOCK_SELECT
  } mock_state_t;
  
  mock_state_t mock_state = MOCK_IDLE;
  logic [31:0] mock_card_uid = 32'h12345678;
  
  // NFC command/response handler
  integer delay_counter;
  logic cmd_processing;
  logic irq_prev_mock;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nfc_cmd_ready <= 1'b1;
      nfc_cmd_done <= 1'b0;
      nfc_cmd_rdata <= 8'h00;
      mock_state <= MOCK_IDLE;
      delay_counter <= 0;
      cmd_processing <= 1'b0;
      irq_prev_mock <= 1'b0;
    end else begin
      irq_prev_mock <= nfc_irq;
      
      // Reset mock state on new card detection (rising edge of IRQ)
      if (nfc_irq && !irq_prev_mock) begin
        mock_state <= MOCK_IDLE;
        $display("[%0t] [MOCK] Reset for new card", $time);
      end
      nfc_cmd_done <= 1'b0;
      
      if (cmd_processing) begin
        delay_counter <= delay_counter + 1;
        if (delay_counter >= 5) begin  // 5 cycles processing delay
          cmd_processing <= 1'b0;
          nfc_cmd_done <= 1'b1;  // Signal done AFTER processing
          nfc_cmd_ready <= 1'b1;
          delay_counter <= 0;
        end
      end else if (nfc_cmd_valid && nfc_cmd_ready) begin
        // Start command processing
        nfc_cmd_ready <= 1'b0;
        cmd_processing <= 1'b1;
        delay_counter <= 0;
        
        // Latch the command and prepare response (will be sent when processing completes)
        if (nfc_cmd_write) begin
          $display("[%0t] [MOCK] Received command: 0x%02h, state=%0d", $time, nfc_cmd_wdata, mock_state);
          case (nfc_cmd_wdata)
            8'h26: begin  // REQA
              mock_state <= MOCK_REQA;
              nfc_cmd_rdata <= 8'h04;  // ATQA low byte
              $display("[%0t] [MOCK] Preparing ATQA: 0x04", $time);
            end
            
            8'h93: begin  // ANTICOLL or SELECT
              if (mock_state == MOCK_REQA) begin
                mock_state <= MOCK_ANTICOLL;
                nfc_cmd_rdata <= mock_card_uid[7:0];  // UID first byte
                $display("[%0t] [MOCK] Preparing UID byte: 0x%02h", $time, mock_card_uid[7:0]);
              end else if (mock_state == MOCK_ANTICOLL) begin
                mock_state <= MOCK_SELECT;
                nfc_cmd_rdata <= 8'h08;  // SAK: complete, no cascade
                $display("[%0t] [MOCK] Preparing SAK: 0x08", $time);
              end else begin
                $display("[%0t] [MOCK] ERROR: Unexpected 0x93 in state %0d", $time, mock_state);
                nfc_cmd_rdata <= 8'hFF;
              end
            end
            
            default: begin
              $display("[%0t] [MOCK] ERROR: Unknown command 0x%02h", $time, nfc_cmd_wdata);
              nfc_cmd_rdata <= 8'hFF;  // Error
            end
          endcase
        end
        // Note: nfc_cmd_done will be set after processing delay
      end
    end
  end
  
  // Test sequence
  initial begin
    $dumpfile("tb_nfc_card_detector.vcd");
    $dumpvars(0, tb_nfc_card_detector);
    
    $display("\n=== NFC Card Detector Test ===\n");
    
    // Initialize
    rst_n = 0;
    nfc_irq = 0;
    #50;
    rst_n = 1;
    #100;
    
    // Test 1: Card detection flow
    $display("[TEST 1] Card detection with valid card...");
    #1000;
    nfc_irq = 1;  // Simulate card detected
    #100;
    nfc_irq = 0;
    
    // Wait for detection to complete
    wait(card_ready == 1 || detection_error == 1);
    @(posedge clk);  // Sync to clock edge
    
    if (card_ready) begin
      $display("[PASS] Card detected successfully!");
      $display("       UID: %h", card_uid);
      if (start_auth)
        $display("       ✓ Authentication triggered");
    end else begin
      $display("[FAIL] Card detection failed!");
      $display("       Error code: %h", error_code);
    end
    
    #2000;  // Wait for detector to return to IDLE
    
    // Test 2: Another card detection
    $display("\n[TEST 2] Second card detection...");
    #1000;
    nfc_irq = 1;
    #100;
    nfc_irq = 0;
    
    // Wait for detection to complete
    wait(card_ready == 1 || detection_error == 1);
    @(posedge clk);
    
    if (card_ready) begin
      $display("[PASS] Second card detected!");
      $display("       UID: %h", card_uid);
    end else begin
      $display("[FAIL] Second card detection failed!");
      $display("       Error code: %h", error_code);
    end
    
    #1000;
    
    $display("\n=== Test Complete ===\n");
    $finish;
  end
  
  // Timeout watchdog
  initial begin
    #50000;  // 50us timeout (shorter for debugging)
    $display("[ERROR] Test timeout!");
    $display("       State: card_detected=%b, card_ready=%b, detection_error=%b", 
             card_detected, card_ready, detection_error);
    $finish;
  end

endmodule
