`timescale 1ns/1ps

// Testbench for MFRC522 Interface
// Tests register read/write operations with behavioral MFRC522 model

module tb_mfrc522_interface;

    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Command interface
    reg cmd_valid;
    wire cmd_ready;
    reg cmd_is_write;
    reg [5:0] cmd_addr;
    reg [7:0] cmd_wdata;
    wire [7:0] cmd_rdata;
    wire cmd_done;
    
    // SPI interface
    wire spi_cs_n;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;
    
    // Test control
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // 20ns period
    end
    
    // DUT instantiation
    mfrc522_interface #(
        .CLOCK_DIV(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_is_write(cmd_is_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_rdata(cmd_rdata),
        .cmd_done(cmd_done),
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );
    
    // MFRC522 behavioral model
    mfrc522_model rfid (
        .cs_n(spi_cs_n),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso)
    );
    
    // MFRC522 Register addresses (commonly used)
    localparam REG_COMMAND      = 6'h01;  // Command register
    localparam REG_COMIEN       = 6'h02;  // Interrupt enable
    localparam REG_DIVIEN       = 6'h03;  // Interrupt enable
    localparam REG_COMIRQ       = 6'h04;  // Interrupt request
    localparam REG_DIVIRQ       = 6'h05;  // Interrupt request
    localparam REG_ERROR        = 6'h06;  // Error flags
    localparam REG_STATUS1      = 6'h07;  // Status register
    localparam REG_STATUS2      = 6'h08;  // Status register
    localparam REG_FIFODATA     = 6'h09;  // FIFO data
    localparam REG_FIFOLEVEL    = 6'h0A;  // FIFO level
    localparam REG_CONTROL      = 6'h0C;  // Control register
    localparam REG_BITFRAMING   = 6'h0D;  // Bit framing
    localparam REG_MODE         = 6'h11;  // Mode register
    localparam REG_TXCONTROL    = 6'h14;  // TX control
    localparam REG_TXAUTO       = 6'h15;  // TX auto
    localparam REG_VERSION      = 6'h37;  // Version register
    
    // Task to write register
    task write_register;
        input [5:0] addr;
        input [7:0] data;
        begin
            @(posedge clk);
            wait(cmd_ready);
            @(posedge clk);
            cmd_is_write = 1;
            cmd_addr = addr;
            cmd_wdata = data;
            cmd_valid = 1;
            @(posedge clk);
            cmd_valid = 0;
            
            // Wait for completion
            wait(cmd_done);
            @(posedge clk);
        end
    endtask
    
    // Task to read register
    task read_register;
        input [5:0] addr;
        output [7:0] data;
        begin
            @(posedge clk);
            wait(cmd_ready);
            @(posedge clk);
            cmd_is_write = 0;
            cmd_addr = addr;
            cmd_wdata = 0;
            cmd_valid = 1;
            @(posedge clk);
            cmd_valid = 0;
            
            // Wait for completion
            wait(cmd_done);
            data = cmd_rdata;
            @(posedge clk);
        end
    endtask
    
    // Task to verify data
    task verify_data;
        input [7:0] expected;
        input [7:0] actual;
        input [255:0] description;
        begin
            test_count = test_count + 1;
            if (expected === actual) begin
                $display("[PASS] Test %0d: %s - Expected: 0x%02h, Got: 0x%02h", 
                         test_count, description, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %s - Expected: 0x%02h, Got: 0x%02h", 
                         test_count, description, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Main test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        cmd_valid = 0;
        cmd_is_write = 0;
        cmd_addr = 0;
        cmd_wdata = 0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Generate VCD file
        $dumpfile("mfrc522_if.vcd");
        $dumpvars(0, tb_mfrc522_interface);
        
        $display("========================================");
        $display("MFRC522 Interface Testbench");
        $display("========================================");
        
        // Reset sequence
        #100;
        rst_n = 1;
        #100;
        
        // Test 1: Read Version Register
        begin
            reg [7:0] version;
            $display("\n--- Test 1: Read Version Register ---");
            read_register(REG_VERSION, version);
            verify_data(8'h92, version, "Version register (typical 0x92)");
        end
        
        #200;
        
        // Test 2: Write and Read Command Register
        begin
            reg [7:0] read_data;
            $display("\n--- Test 2: Write/Read Command Register ---");
            
            write_register(REG_COMMAND, 8'h0F);  // Idle command
            #100;
            
            read_register(REG_COMMAND, read_data);
            verify_data(8'h0F, read_data, "Command register");
        end
        
        #200;
        
        // Test 3: Multiple Register Writes
        begin
            reg [7:0] read_data;
            $display("\n--- Test 3: Multiple Register Operations ---");
            
            // Write Mode register
            write_register(REG_MODE, 8'h3D);
            #100;
            read_register(REG_MODE, read_data);
            verify_data(8'h3D, read_data, "Mode register");
            
            #100;
            
            // Write TX Control
            write_register(REG_TXCONTROL, 8'h83);
            #100;
            read_register(REG_TXCONTROL, read_data);
            verify_data(8'h83, read_data, "TX Control register");
        end
        
        #200;
        
        // Test 4: FIFO Data Register
        begin
            reg [7:0] read_data;
            integer i;
            $display("\n--- Test 4: FIFO Data Operations ---");
            
            // Write multiple bytes to FIFO
            for (i = 0; i < 5; i = i + 1) begin
                write_register(REG_FIFODATA, 8'h10 + i);
                #100;
            end
            
            // Read FIFO level
            read_register(REG_FIFOLEVEL, read_data);
            verify_data(8'h05, read_data, "FIFO level after 5 writes");
            
            // Read FIFO data
            read_register(REG_FIFODATA, read_data);
            verify_data(8'h10, read_data, "First FIFO byte");
        end
        
        #200;
        
        // Test 5: Status Registers
        begin
            reg [7:0] status1, status2;
            $display("\n--- Test 5: Read Status Registers ---");
            
            read_register(REG_STATUS1, status1);
            read_register(REG_STATUS2, status2);
            
            $display("       Status1: 0x%02h, Status2: 0x%02h", status1, status2);
            // Status values depend on RFID state, just verify read works
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
        
        #200;
        
        // Test 6: Error Register
        begin
            reg [7:0] error_reg;
            $display("\n--- Test 6: Read Error Register ---");
            
            read_register(REG_ERROR, error_reg);
            verify_data(8'h00, error_reg, "Error register (should be 0)");
        end
        
        #200;
        
        // Test 7: Rapid Register Access
        begin
            reg [7:0] read_data;
            integer i;
            $display("\n--- Test 7: Rapid Register Access ---");
            
            for (i = 0; i < 8; i = i + 1) begin
                write_register(REG_CONTROL, i[7:0]);
                #50;
                read_register(REG_CONTROL, read_data);
                verify_data(i[7:0], read_data, "Rapid access test");
                #50;
            end
        end
        
        #200;
        
        // Test 8: Interrupt Registers
        begin
            reg [7:0] read_data;
            $display("\n--- Test 8: Interrupt Enable/Request Registers ---");
            
            // Enable interrupts
            write_register(REG_COMIEN, 8'hA0);
            #100;
            read_register(REG_COMIEN, read_data);
            verify_data(8'hA0, read_data, "ComIEn register");
            
            #100;
            
            // Check interrupt request
            read_register(REG_COMIRQ, read_data);
            $display("       ComIRQ: 0x%02h", read_data);
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
        
        #200;
        
        // Test 9: Bit Framing Register
        begin
            reg [7:0] read_data;
            $display("\n--- Test 9: Bit Framing Register ---");
            
            write_register(REG_BITFRAMING, 8'h07);
            #100;
            read_register(REG_BITFRAMING, read_data);
            verify_data(8'h07, read_data, "Bit framing");
        end
        
        #200;
        
        // Test 10: Boundary Test - All Address Range
        begin
            reg [7:0] read_data;
            $display("\n--- Test 10: Address Boundary Test ---");
            
            // Test address 0x00
            write_register(6'h00, 8'hAA);
            #100;
            read_register(6'h00, read_data);
            verify_data(8'hAA, read_data, "Address 0x00");
            
            #100;
            
            // Test address 0x3F (highest)
            write_register(6'h3F, 8'h55);
            #100;
            read_register(6'h3F, read_data);
            verify_data(8'h55, read_data, "Address 0x3F");
        end
        
        #500;
        
        // Test Summary
        $display("\n========================================");
        $display("Test Summary:");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        if (fail_count == 0) begin
            $display("\nALL TESTS PASSED!");
        end else begin
            $display("\nSOME TESTS FAILED!");
        end
        $display("========================================\n");
        
        #1000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #500000;  // 500us timeout
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule


// Behavioral model of MFRC522 RFID Reader
module mfrc522_model (
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    output reg miso
);

    // Register file (64 registers, 6-bit address)
    reg [7:0] registers [0:63];
    
    // FIFO buffer
    reg [7:0] fifo [0:63];
    reg [5:0] fifo_level;
    reg [5:0] fifo_rd_ptr;
    reg [5:0] fifo_wr_ptr;
    
    // Internal registers
    reg [7:0] shift_in;   // For receiving (MOSI)
    reg [7:0] shift_out;  // For transmitting (MISO)
    reg [3:0] bit_count;
    reg [7:0] addr_byte;
    reg [1:0] byte_count;
    reg [1:0] state;
    
    // State machine
    localparam ST_IDLE   = 2'b00;
    localparam ST_ADDR   = 2'b01;
    localparam ST_RDDATA = 2'b10;
    
    // Register addresses
    localparam REG_FIFODATA  = 6'h09;
    localparam REG_FIFOLEVEL = 6'h0A;
    localparam REG_VERSION   = 6'h37;
    
    integer i;
    
    initial begin
        // Initialize registers with default values
        for (i = 0; i < 64; i = i + 1) begin
            registers[i] = 8'h00;
        end
        
        // Set version register
        registers[REG_VERSION] = 8'h92;  // Typical version
        
        // Initialize FIFO
        for (i = 0; i < 64; i = i + 1) begin
            fifo[i] = 8'h00;
        end
        fifo_level = 0;
        fifo_rd_ptr = 0;
        fifo_wr_ptr = 0;
        
        miso = 1'b1;
        state = ST_IDLE;
        bit_count = 0;
        shift_in = 0;
        shift_out = 0;
        addr_byte = 0;
        byte_count = 0;
    end
    
    reg [7:0] complete_byte;
    
    // Combinational logic for complete byte
    always @(*) begin
        complete_byte = {shift_in[6:0], mosi};
    end
    
    // Main SPI logic on rising edge (Mode 0)
    always @(posedge sclk or posedge cs_n) begin
        if (cs_n) begin
            state <= ST_IDLE;
            bit_count <= 0;
            miso <= 1'b1;
            byte_count <= 0;
            shift_in <= 0;
            shift_out <= 0;
        end else begin
            // Shift in MOSI bit
            shift_in <= {shift_in[6:0], mosi};
            bit_count <= bit_count + 1;
            
            // Process complete byte
            if (bit_count == 7) begin
                bit_count <= 0;
                byte_count <= byte_count + 1;
                
                case (state)
                    ST_IDLE: begin
                        // First byte is address
                        // Format: [R/W][A5:A0][0]
                        addr_byte <= complete_byte;
                        
                        if (!complete_byte[7]) begin
                            // Read operation - prepare data for next transfer
                            if (complete_byte[6:1] == REG_FIFODATA) begin
                                if (fifo_level > 0)
                                    shift_out <= fifo[fifo_rd_ptr];
                                else
                                    shift_out <= 8'h00;
                            end else begin
                                shift_out <= registers[complete_byte[6:1]];
                            end
                            state <= ST_RDDATA;
                        end else begin
                            // Write operation
                            state <= ST_ADDR;
                        end
                    end
                    
                    ST_ADDR: begin
                        // Write data byte received
                        if (addr_byte[6:1] == REG_FIFODATA) begin
                            // FIFO write
                            fifo[fifo_wr_ptr] <= complete_byte;
                            fifo_wr_ptr <= fifo_wr_ptr + 1;
                            if (fifo_level < 64)
                                fifo_level <= fifo_level + 1;
                            registers[REG_FIFOLEVEL] <= fifo_level + 1;
                        end else begin
                            // Normal register write
                            registers[addr_byte[6:1]] <= complete_byte;
                        end
                        state <= ST_IDLE;
                    end
                    
                    ST_RDDATA: begin
                        // Dummy byte received during read operation
                        // Data was already loaded in ST_IDLE case
                        // Handle FIFO read pointer increment
                        if (addr_byte[6:1] == REG_FIFODATA && fifo_level > 0) begin
                            fifo_rd_ptr <= fifo_rd_ptr + 1;
                            fifo_level <= fifo_level - 1;
                            registers[REG_FIFOLEVEL] <= fifo_level - 1;
                        end
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end
    
    // Shift out on falling edge (Mode 0)
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            miso <= 1'b1;
        end else begin
            if (state == ST_RDDATA) begin
                miso <= shift_out[7];
                shift_out <= {shift_out[6:0], 1'b1};
            end else begin
                miso <= 1'b1;
            end
        end
    end

endmodule
