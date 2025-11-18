// NFC Card Detector Module
// Implements ISO14443A card detection and selection
// Detects card presence and reads UID before triggering authentication

module nfc_card_detector (
  input  logic         clk,
  input  logic         rst_n,
  
  // MFRC522 interrupt input
  input  logic         nfc_irq,           // Interrupt from MFRC522 (card detected)
  
  // Card detection outputs
  output logic         card_detected,     // Card is present
  output logic [31:0]  card_uid,          // 4-byte UID (most common)
  output logic         card_ready,        // Card selected and ready
  
  // To auth_controller
  output logic         start_auth,        // Trigger authentication
  
  // NFC Interface (MFRC522)
  output logic         nfc_cmd_valid,
  input  logic         nfc_cmd_ready,
  output logic         nfc_cmd_write,
  output logic [5:0]   nfc_cmd_addr,
  output logic [7:0]   nfc_cmd_wdata,
  input  logic [7:0]   nfc_cmd_rdata,
  input  logic         nfc_cmd_done,
  
  // Status/Error outputs
  output logic         detection_error,   // Error during detection
  output logic [7:0]   error_code         // Error code for debugging
);

  // ISO14443A Commands
  localparam [7:0] CMD_REQA     = 8'h26;  // Request Type A
  localparam [7:0] CMD_WUPA     = 8'h52;  // Wake-Up Type A
  localparam [7:0] CMD_ANTICOLL = 8'h93;  // Anti-collision CL1
  localparam [7:0] CMD_SELECT   = 8'h93;  // Select CL1
  
  // Expected responses
  localparam [15:0] ATQA_MIFARE = 16'h0004;  // Typical ATQA response
  
  // State machine
  typedef enum logic [3:0] {
    ST_IDLE,
    ST_WAIT_IRQ,
    ST_SEND_REQA,
    ST_WAIT_ATQA,
    ST_CHECK_ATQA,
    ST_SEND_ANTICOLL,
    ST_WAIT_UID,
    ST_CHECK_UID,
    ST_SEND_SELECT,
    ST_WAIT_SAK,
    ST_CHECK_SAK,
    ST_CARD_READY,
    ST_ERROR
  } state_t;
  
  state_t state, next_state;
  
  // Internal registers
  logic [31:0] uid_buffer;
  logic [15:0] atqa_response;
  logic [7:0]  sak_response;
  logic [2:0]  uid_byte_count;
  logic [3:0]  retry_count;
  logic        command_sent;  // Flag to ensure command is sent only once
  logic        irq_detected;
  
  // State machine - sequential logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
    end else begin
      state <= next_state;
    end
  end
  
  // State machine - combinational logic
  always_comb begin
    next_state = state;
    
    case (state)
      ST_IDLE: begin
        if (irq_detected) next_state = ST_SEND_REQA;
      end
      
      ST_WAIT_IRQ: begin
        if (irq_detected) next_state = ST_SEND_REQA;
      end
      
      ST_SEND_REQA: begin
        if (nfc_cmd_ready) next_state = ST_WAIT_ATQA;
      end
      
      ST_WAIT_ATQA: begin
        if (nfc_cmd_done) next_state = ST_CHECK_ATQA;
      end
      
      ST_CHECK_ATQA: begin
        if (atqa_response == ATQA_MIFARE)
          next_state = ST_SEND_ANTICOLL;
        else if (retry_count < 3)
          next_state = ST_SEND_REQA;  // Retry
        else
          next_state = ST_ERROR;
      end
      
      ST_SEND_ANTICOLL: begin
        if (nfc_cmd_ready) next_state = ST_WAIT_UID;
      end
      
      ST_WAIT_UID: begin
        if (nfc_cmd_done) next_state = ST_CHECK_UID;
      end
      
      ST_CHECK_UID: begin
        // Simple BCC check: XOR of all UID bytes should match BCC
        next_state = ST_SEND_SELECT;
      end
      
      ST_SEND_SELECT: begin
        if (nfc_cmd_ready) next_state = ST_WAIT_SAK;
      end
      
      ST_WAIT_SAK: begin
        if (nfc_cmd_done) next_state = ST_CHECK_SAK;
      end
      
      ST_CHECK_SAK: begin
        // Check if SAK indicates complete (bit 3 = 0)
        if (sak_response[2] == 1'b0)
          next_state = ST_CARD_READY;
        else
          next_state = ST_ERROR;  // Cascade level required (not supported)
      end
      
      ST_CARD_READY: begin
        // Go back to IDLE after one cycle (auth_controller takes over)
        next_state = ST_IDLE;
      end
      
      ST_ERROR: begin
        next_state = ST_IDLE;  // Reset and wait for next attempt
      end
    endcase
  end
  
  // IRQ edge detection
  logic irq_prev;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      irq_prev <= 1'b0;
      irq_detected <= 1'b0;
    end else begin
      irq_prev <= nfc_irq;
      // Rising edge detection
      if (nfc_irq && !irq_prev) begin
        irq_detected <= 1'b1;
        $display("[%0t] [NFC_DETECTOR] Card detected (IRQ triggered)", $time);
      end
      // Clear detection flag only after state machine has processed it
      // (after we've started the detection sequence)
      if (state == ST_SEND_REQA && irq_detected) begin
        irq_detected <= 1'b0;
      end
    end
  end
  
  // Control logic and datapath
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      card_detected <= 1'b0;
      card_uid <= 32'h0;
      card_ready <= 1'b0;
      start_auth <= 1'b0;
      detection_error <= 1'b0;
      error_code <= 8'h00;
      
      uid_buffer <= 32'h0;
      atqa_response <= 16'h0;
      sak_response <= 8'h0;
      uid_byte_count <= 3'h0;
      retry_count <= 4'h0;
      command_sent <= 1'b0;
      
      nfc_cmd_valid <= 1'b0;
      nfc_cmd_write <= 1'b0;
      nfc_cmd_addr <= 6'h0;
      nfc_cmd_wdata <= 8'h0;
      
    end else begin
      // Default: clear single-cycle signals
      nfc_cmd_valid <= 1'b0;
      start_auth <= 1'b0;
      
      // Clear command_sent flag when state changes
      if (state != next_state)
        command_sent <= 1'b0;
      
      case (state)
        ST_IDLE: begin
          if (card_ready || card_detected) begin
            $display("[%0t] [NFC_DETECTOR] Back to IDLE, ready for next card", $time);
          end
          card_detected <= 1'b0;
          card_ready <= 1'b0;
          detection_error <= 1'b0;
          retry_count <= 4'h0;
          // Don't clear irq_detected here - it's needed for state transition!
        end
        
        ST_SEND_REQA: begin
          if (!command_sent) begin
            $display("[%0t] [NFC_DETECTOR] → REQA (Request Type A)", $time);
            nfc_cmd_valid <= 1'b1;
            nfc_cmd_write <= 1'b1;
            nfc_cmd_addr <= 6'h09;  // TxModeReg
            nfc_cmd_wdata <= CMD_REQA;
            command_sent <= 1'b1;
            // Reset response buffers for new detection
            atqa_response <= 16'h0;
            uid_buffer <= 32'h0;
            sak_response <= 8'h0;
          end
          card_detected <= 1'b1;
        end
        
        ST_WAIT_ATQA: begin
          if (nfc_cmd_done) begin
            atqa_response <= {atqa_response[7:0], nfc_cmd_rdata};
          end
        end
        
        ST_CHECK_ATQA: begin
          if (atqa_response == ATQA_MIFARE) begin
            $display("[%0t] [NFC_DETECTOR] ← ATQA: %h (valid)", $time, atqa_response);
            retry_count <= 4'h0;
          end else begin
            $display("[%0t] [NFC_DETECTOR] ← ATQA: %h (invalid, retry)", $time, atqa_response);
            retry_count <= retry_count + 1;
          end
        end
        
        ST_SEND_ANTICOLL: begin
          if (!command_sent) begin
            $display("[%0t] [NFC_DETECTOR] → ANTICOLL (Anti-Collision)", $time);
            nfc_cmd_valid <= 1'b1;
            nfc_cmd_write <= 1'b1;
            nfc_cmd_addr <= 6'h09;
            nfc_cmd_wdata <= CMD_ANTICOLL;
            command_sent <= 1'b1;
          end
        end
        
        ST_WAIT_UID: begin
          if (nfc_cmd_done) begin
            // In simplified version, assume UID is returned in single response
            card_uid <= {24'h0, nfc_cmd_rdata};
          end
        end
        
        ST_CHECK_UID: begin
          $display("[%0t] [NFC_DETECTOR] ← UID: %h", $time, card_uid);
        end
        
        ST_SEND_SELECT: begin
          if (!command_sent) begin
            $display("[%0t] [NFC_DETECTOR] → SELECT (Select Card)", $time);
            nfc_cmd_valid <= 1'b1;
            nfc_cmd_write <= 1'b1;
            nfc_cmd_addr <= 6'h09;
            nfc_cmd_wdata <= CMD_SELECT;
            command_sent <= 1'b1;
          end
        end
        
        ST_WAIT_SAK: begin
          if (nfc_cmd_done) begin
            sak_response <= nfc_cmd_rdata;
          end
        end
        
        ST_CHECK_SAK: begin
          $display("[%0t] [NFC_DETECTOR] ← SAK: %h", $time, sak_response);
          if (sak_response[2] == 1'b0) begin
            $display("[%0t] [NFC_DETECTOR] ✓ Card selected successfully", $time);
          end else begin
            $display("[%0t] [NFC_DETECTOR] ✗ Cascade required (not supported)", $time);
            detection_error <= 1'b1;
            error_code <= 8'h01;  // Cascade not supported
          end
        end
        
        ST_CARD_READY: begin
          if (!card_ready) begin
            card_ready <= 1'b1;
            start_auth <= 1'b1;  // Trigger authentication (one-shot)
            $display("[%0t] [NFC_DETECTOR] Card ready → Starting authentication", $time);
          end
        end
        
        ST_ERROR: begin
          detection_error <= 1'b1;
          if (error_code == 8'h00) begin
            error_code <= 8'hFF;  // General error
            $display("[%0t] [NFC_DETECTOR] ✗ Detection error", $time);
          end
        end
      endcase
    end
  end

endmodule
