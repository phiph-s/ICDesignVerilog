// Authentication Controller Module
// Implements LAYR Authenticated Identification Protocol
// Challenge-Response with AES-128 ECB encryption

module auth_controller (
  input  logic         clk,
  input  logic         rst_n,
  
  // Control interface
  input  logic         start_auth,      // Start authentication sequence
  output logic         auth_success,    // Authentication successful
  output logic         auth_failed,     // Authentication failed
  output logic         auth_busy,       // Authentication in progress
  
  // Card ID output
  output logic [127:0] card_id,         // Decrypted card ID
  output logic         card_id_valid,   // Card ID is valid
  
  // AES Core interface
  output logic         aes_start,
  output logic         aes_mode,        // 0=encrypt, 1=decrypt
  output logic [127:0] aes_key,
  output logic [127:0] aes_block_in,
  input  logic [127:0] aes_block_out,
  input  logic         aes_done,
  
  // Key Storage (EEPROM) interface
  output logic         key_load_req,
  output logic [6:0]   key_addr,        // EEPROM address for PSK
  input  logic [7:0]   key_data,        // Key data byte
  input  logic         key_data_valid,
  
  // Nonce Generator interface
  output logic         nonce_req,
  input  logic [63:0]  nonce,
  input  logic         nonce_valid,
  
  // NFC Interface (MFRC522) interface
  output logic         nfc_cmd_valid,
  input  logic         nfc_cmd_ready,
  output logic         nfc_cmd_write,
  output logic [5:0]   nfc_cmd_addr,
  output logic [7:0]   nfc_cmd_wdata,
  input  logic [7:0]   nfc_cmd_rdata,
  input  logic         nfc_cmd_done,
  
  // Timeout watchdog
  output logic         timeout_start,
  input  logic         timeout_occurred
);

  // Protocol command codes (CLA INS)
  localparam [15:0] CMD_AUTH_INIT = 16'h8010;
  localparam [15:0] CMD_AUTH      = 16'h8011;
  localparam [15:0] CMD_GET_ID    = 16'h8012;
  
  // State machine
  typedef enum logic [4:0] {
    ST_IDLE,
    ST_LOAD_KEY_START,
    ST_LOAD_KEY_WAIT,
    ST_LOAD_KEY_BYTES,
    ST_AUTH_INIT_SEND,
    ST_AUTH_INIT_WAIT,
    ST_AUTH_INIT_READ,
    ST_DECRYPT_RC,
    ST_DECRYPT_RC_WAIT,
    ST_GEN_NONCE,
    ST_GEN_NONCE_WAIT,
    ST_ENCRYPT_AUTH,
    ST_ENCRYPT_AUTH_WAIT,
    ST_AUTH_SEND,
    ST_AUTH_WAIT,
    ST_DERIVE_SESSION_KEY,
    ST_DERIVE_SESSION_KEY_WAIT,
    ST_GET_ID_SEND,
    ST_GET_ID_WAIT,
    ST_GET_ID_READ,
    ST_DECRYPT_ID,
    ST_DECRYPT_ID_WAIT,
    ST_SUCCESS,
    ST_FAILED
  } state_t;
  
  state_t state, next_state;
  
  // Internal registers
  logic [127:0] psk;                    // Pre-shared key
  logic [63:0]  rc;                     // Card challenge
  logic [63:0]  rt;                     // Terminal challenge
  logic [127:0] session_key;            // Ephemeral session key
  logic [127:0] encrypted_rc;           // Encrypted challenge from card
  logic [127:0] encrypted_id;           // Encrypted card ID
  logic [3:0]   key_byte_counter;       // Counter for loading 16-byte key
  logic [7:0]   fifo_byte_counter;      // Counter for FIFO operations
  
  // Key loading from EEPROM (16 bytes starting at address 0x00)
  localparam [6:0] KEY_BASE_ADDR = 7'h00;
  
  // State machine - sequential logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
    end else begin
      if (timeout_occurred && state != ST_IDLE && state != ST_SUCCESS && state != ST_FAILED) begin
        state <= ST_FAILED;
      end else begin
        state <= next_state;
      end
    end
  end
  
  // State machine - combinational logic
  always_comb begin
    next_state = state;
    
    case (state)
      ST_IDLE: begin
        if (start_auth) next_state = ST_LOAD_KEY_START;
      end
      
      ST_LOAD_KEY_START: begin
        next_state = ST_LOAD_KEY_WAIT;
      end
      
      ST_LOAD_KEY_WAIT: begin
        if (key_data_valid) begin
          if (key_byte_counter == 15)
            next_state = ST_AUTH_INIT_SEND;
          else
            next_state = ST_LOAD_KEY_BYTES;
        end
      end
      
      ST_LOAD_KEY_BYTES: begin
        if (key_data_valid) begin
          if (key_byte_counter == 15)
            next_state = ST_AUTH_INIT_SEND;
          else
            next_state = ST_LOAD_KEY_WAIT;
        end
      end
      
      ST_AUTH_INIT_SEND: begin
        if (nfc_cmd_ready) next_state = ST_AUTH_INIT_WAIT;
      end
      
      ST_AUTH_INIT_WAIT: begin
        if (nfc_cmd_done) next_state = ST_AUTH_INIT_READ;
      end
      
      ST_AUTH_INIT_READ: begin
        if (fifo_byte_counter == 16) next_state = ST_DECRYPT_RC;
      end
      
      ST_DECRYPT_RC: begin
        next_state = ST_DECRYPT_RC_WAIT;
      end
      
      ST_DECRYPT_RC_WAIT: begin
        if (aes_done) next_state = ST_GEN_NONCE;
      end
      
      ST_GEN_NONCE: begin
        next_state = ST_GEN_NONCE_WAIT;
      end
      
      ST_GEN_NONCE_WAIT: begin
        if (nonce_valid) next_state = ST_ENCRYPT_AUTH;
      end
      
      ST_ENCRYPT_AUTH: begin
        next_state = ST_ENCRYPT_AUTH_WAIT;
      end
      
      ST_ENCRYPT_AUTH_WAIT: begin
        if (aes_done) next_state = ST_AUTH_SEND;
      end
      
      ST_AUTH_SEND: begin
        if (nfc_cmd_ready) next_state = ST_AUTH_WAIT;
      end
      
      ST_AUTH_WAIT: begin
        // Check card's response - 0xFF indicates auth failure
        if (nfc_cmd_done) begin
          if (nfc_cmd_rdata == 8'hFF)
            next_state = ST_FAILED;
          else
            next_state = ST_DERIVE_SESSION_KEY;
        end
      end
      
      ST_DERIVE_SESSION_KEY: begin
        next_state = ST_DERIVE_SESSION_KEY_WAIT;
      end
      
      ST_DERIVE_SESSION_KEY_WAIT: begin
        if (aes_done) next_state = ST_GET_ID_SEND;
      end
      
      ST_GET_ID_SEND: begin
        if (nfc_cmd_ready) next_state = ST_GET_ID_WAIT;
      end
      
        ST_GET_ID_WAIT: begin
          // Check if card responds with error (card not authenticated)
          if (nfc_cmd_done) begin
            if (nfc_cmd_rdata == 8'hFF)
              next_state = ST_FAILED;
            else
              next_state = ST_GET_ID_READ;
          end
        end      ST_GET_ID_READ: begin
        if (fifo_byte_counter == 16) next_state = ST_DECRYPT_ID;
      end
      
      ST_DECRYPT_ID: begin
        next_state = ST_DECRYPT_ID_WAIT;
      end
      
      ST_DECRYPT_ID_WAIT: begin
        if (aes_done) next_state = ST_SUCCESS;
      end
      
      ST_SUCCESS: begin
        next_state = ST_IDLE;
      end
      
      ST_FAILED: begin
        next_state = ST_IDLE;
      end
    endcase
  end
  
  // Control logic and datapath
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psk <= 128'h0;
      rc <= 64'h0;
      rt <= 64'h0;
      session_key <= 128'h0;
      encrypted_rc <= 128'h0;
      encrypted_id <= 128'h0;
      card_id <= 128'h0;
      key_byte_counter <= 4'h0;
      fifo_byte_counter <= 8'h0;
      
      auth_success <= 1'b0;
      auth_failed <= 1'b0;
      card_id_valid <= 1'b0;
      
      aes_start <= 1'b0;
      aes_mode <= 1'b0;
      aes_key <= 128'h0;
      aes_block_in <= 128'h0;
      
      key_load_req <= 1'b0;
      key_addr <= 7'h0;
      
      nonce_req <= 1'b0;
      
      nfc_cmd_valid <= 1'b0;
      nfc_cmd_write <= 1'b0;
      nfc_cmd_addr <= 6'h0;
      nfc_cmd_wdata <= 8'h0;
      
      timeout_start <= 1'b0;
      
    end else begin
      // Default: clear single-cycle signals
      aes_start <= 1'b0;
      key_load_req <= 1'b0;
      nonce_req <= 1'b0;
      nfc_cmd_valid <= 1'b0;
      timeout_start <= 1'b0;
      auth_success <= 1'b0;
      auth_failed <= 1'b0;
      
      case (state)
        ST_IDLE: begin
          card_id_valid <= 1'b0;
          key_byte_counter <= 4'h0;
          if (start_auth) begin
            timeout_start <= 1'b1;
          end
        end
        
        ST_LOAD_KEY_START: begin
          key_load_req <= 1'b1;
          key_addr <= KEY_BASE_ADDR;
          key_byte_counter <= 4'h0;
        end
        
        ST_LOAD_KEY_WAIT: begin
          if (key_data_valid) begin
            // Store first byte in MSB position
            psk <= {key_data, psk[119:0]};
            key_byte_counter <= key_byte_counter + 1;
            
            // Request next byte if not done
            if (key_byte_counter < 15) begin
              key_load_req <= 1'b1;
              key_addr <= KEY_BASE_ADDR + key_byte_counter + 1;
            end
          end
        end
        
        ST_LOAD_KEY_BYTES: begin
          if (key_data_valid) begin
            // Shift in key bytes
            psk <= {key_data, psk[119:0]};
            key_byte_counter <= key_byte_counter + 1;
            
            // Request next byte if not done
            if (key_byte_counter < 15) begin
              key_load_req <= 1'b1;
              key_addr <= KEY_BASE_ADDR + key_byte_counter + 1;
            end
          end
        end
        
        ST_AUTH_INIT_SEND: begin
          // Send AUTH_INIT command (0x80 0x10) to card via NFC
          // This is simplified - actual implementation needs APDU framing
          nfc_cmd_valid <= 1'b1;
          nfc_cmd_write <= 1'b1;
          nfc_cmd_wdata <= 8'h80;  // CLA
          fifo_byte_counter <= 8'h0;
        end
        
        ST_AUTH_INIT_READ: begin
          // Read 16 bytes of encrypted challenge from card
          // In a real implementation, this would read from NFC FIFO
          // For now, we simulate receiving all 16 bytes at once
          encrypted_rc <= {encrypted_rc[119:0], nfc_cmd_rdata};
          fifo_byte_counter <= fifo_byte_counter + 1;
        end
        
        ST_DECRYPT_RC: begin
          // Decrypt encrypted challenge to recover rc
          aes_start <= 1'b1;
          aes_mode <= 1'b1;  // Decrypt
          aes_key <= psk;
          aes_block_in <= encrypted_rc;
        end
        
        ST_DECRYPT_RC_WAIT: begin
          if (aes_done) begin
            rc <= aes_block_out[127:64];  // Upper 8 bytes
          end
        end
        
        ST_GEN_NONCE: begin
          // Generate terminal challenge rt
          nonce_req <= 1'b1;
        end
        
        ST_GEN_NONCE_WAIT: begin
          if (nonce_valid) begin
            rt <= nonce;
          end
        end
        
        ST_ENCRYPT_AUTH: begin
          // Encrypt AES_psk(rt || rc)
          aes_start <= 1'b1;
          aes_mode <= 1'b0;  // Encrypt
          aes_key <= psk;
          aes_block_in <= {rt, rc};
        end
        
        ST_AUTH_SEND: begin
          // Send AUTH command with encrypted response
          nfc_cmd_valid <= 1'b1;
          nfc_cmd_write <= 1'b1;
          nfc_cmd_wdata <= 8'h80;  // CLA (simplified)
        end
        
        ST_DERIVE_SESSION_KEY: begin
          // Compute session key: k_eph = AES_psk(rc || rt)
          aes_start <= 1'b1;
          aes_mode <= 1'b0;  // Encrypt
          aes_key <= psk;
          aes_block_in <= {rc, rt};
        end
        
        ST_DERIVE_SESSION_KEY_WAIT: begin
          if (aes_done) begin
            session_key <= aes_block_out;
          end
        end
        
        ST_GET_ID_SEND: begin
          // Send GET_ID command
          nfc_cmd_valid <= 1'b1;
          nfc_cmd_write <= 1'b1;
          nfc_cmd_wdata <= 8'h80;  // CLA
          fifo_byte_counter <= 8'h0;
        end
        
        ST_GET_ID_READ: begin
          // Read 16 bytes of encrypted card ID
          // In a real implementation, this would read from NFC FIFO
          // For now, we simulate receiving all 16 bytes at once
          encrypted_id <= {encrypted_id[119:0], nfc_cmd_rdata};
          fifo_byte_counter <= fifo_byte_counter + 1;
        end
        
        ST_DECRYPT_ID: begin
          // Decrypt card ID with session key
          aes_start <= 1'b1;
          aes_mode <= 1'b1;  // Decrypt
          aes_key <= session_key;
          aes_block_in <= encrypted_id;
        end
        
        ST_DECRYPT_ID_WAIT: begin
          if (aes_done) begin
            card_id <= aes_block_out;
            card_id_valid <= 1'b1;
          end
        end
        
        ST_SUCCESS: begin
          auth_success <= 1'b1;
        end
        
        ST_FAILED: begin
          auth_failed <= 1'b1;
        end
      endcase
    end
  end
  
  // Auth busy signal
  assign auth_busy = (state != ST_IDLE) && (state != ST_SUCCESS) && (state != ST_FAILED);

endmodule
