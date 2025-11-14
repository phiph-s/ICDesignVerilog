`timescale 1ns/1ps

// Testbench for AT25010 Interface
// Tests all AT25010 commands with a behavioral EEPROM model

module tb_at25010_interface;

    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Command interface
    reg cmd_valid;
    wire cmd_ready;
    reg [2:0] cmd_type;
    reg [6:0] cmd_addr;
    reg [7:0] cmd_wdata;
    wire [7:0] cmd_rdata;
    wire cmd_done;
    wire cmd_error;
    
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
    at25010_interface #(
        .CLKS_PER_HALF_BIT(2),
        .MAX_BYTES_PER_CS(3),
        .CS_INACTIVE_CLKS(10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_type(cmd_type),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_rdata(cmd_rdata),
        .cmd_done(cmd_done),
        .cmd_error(cmd_error),
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );
    
    // AT25010 behavioral model
    at25010_model eeprom (
        .cs_n(spi_cs_n),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso)
    );
    
    // Command types
    localparam CMD_WREN  = 3'b000;
    localparam CMD_WRDI  = 3'b001;
    localparam CMD_RDSR  = 3'b010;
    localparam CMD_WRSR  = 3'b011;
    localparam CMD_READ  = 3'b100;
    localparam CMD_WRITE = 3'b101;
    
    // Task to send a command
    task send_command;
        input [2:0] cmd;
        input [6:0] addr;
        input [7:0] wdata;
        output [7:0] rdata;
        begin
            @(posedge clk);
            wait(cmd_ready);
            @(posedge clk);
            cmd_type = cmd;
            cmd_addr = addr;
            cmd_wdata = wdata;
            cmd_valid = 1;
            @(posedge clk);
            cmd_valid = 0;
            
            // Wait for command completion
            wait(cmd_done || cmd_error);
            rdata = cmd_rdata;
            @(posedge clk);
            
            if (cmd_error) begin
                $display("[ERROR] Command failed at time %0t", $time);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Task to verify data
    task verify_data;
        input [7:0] expected;
        input [7:0] actual;
        input [127:0] description;
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
        cmd_type = 0;
        cmd_addr = 0;
        cmd_wdata = 0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Generate VCD file
        $dumpfile("at25010_if.vcd");
        $dumpvars(0, tb_at25010_interface);
        
        $display("========================================");
        $display("AT25010 Interface Testbench");
        $display("========================================");
        
        // Reset sequence
        #100;
        rst_n = 1;
        #100;
        
        // Test 1: Read Status Register (should be 0x00 initially)
        begin
            reg [7:0] status;
            $display("\n--- Test 1: Read Status Register ---");
            send_command(CMD_RDSR, 7'h00, 8'h00, status);
            verify_data(8'h00, status, "Initial status");
        end
        
        #200;
        
        // Test 2: Write Enable
        begin
            reg [7:0] dummy;
            $display("\n--- Test 2: Write Enable Command ---");
            send_command(CMD_WREN, 7'h00, 8'h00, dummy);
            #100;
            
            // Verify WEL bit is set
            send_command(CMD_RDSR, 7'h00, 8'h00, dummy);
            verify_data(8'h02, dummy, "Status after WREN (WEL bit)");
        end
        
        #200;
        
        // Test 3: Write Data to EEPROM
        begin
            reg [7:0] dummy;
            $display("\n--- Test 3: Write Data to Address 0x15 ---");
            
            // Enable write
            send_command(CMD_WREN, 7'h00, 8'h00, dummy);
            #100;
            
            // Write data 0xA5 to address 0x15
            send_command(CMD_WRITE, 7'h15, 8'hA5, dummy);
            #500;  // Wait for write cycle
        end
        
        #200;
        
        // Test 4: Read Data from EEPROM
        begin
            reg [7:0] read_data;
            $display("\n--- Test 4: Read Data from Address 0x15 ---");
            send_command(CMD_READ, 7'h15, 8'h00, read_data);
            verify_data(8'hA5, read_data, "Read after write");
        end
        
        #200;
        
        // Test 5: Multiple Write/Read Operations
        begin
            reg [7:0] wdata, rdata, dummy;
            integer i;
            $display("\n--- Test 5: Multiple Write/Read Operations ---");
            
            for (i = 0; i < 8; i = i + 1) begin
                wdata = 8'h10 + i;
                
                // Write enable
                send_command(CMD_WREN, 7'h00, 8'h00, dummy);
                #50;
                
                // Write data
                send_command(CMD_WRITE, i[6:0], wdata, dummy);
                #500;
                
                // Read back
                send_command(CMD_READ, i[6:0], 8'h00, rdata);
                verify_data(wdata, rdata, "Sequential write/read");
                #100;
            end
        end
        
        #200;
        
        // Test 6: Write Disable
        begin
            reg [7:0] status;
            $display("\n--- Test 6: Write Disable Command ---");
            
            // Enable write first
            send_command(CMD_WREN, 7'h00, 8'h00, status);
            #100;
            
            // Disable write
            send_command(CMD_WRDI, 7'h00, 8'h00, status);
            #100;
            
            // Verify WEL bit is cleared
            send_command(CMD_RDSR, 7'h00, 8'h00, status);
            verify_data(8'h00, status, "Status after WRDI");
        end
        
        #200;
        
        // Test 7: Boundary Address Test
        begin
            reg [7:0] wdata, rdata, dummy;
            $display("\n--- Test 7: Boundary Address Test ---");
            
            // Test address 0x00 (first)
            send_command(CMD_WREN, 7'h00, 8'h00, dummy);
            #50;
            send_command(CMD_WRITE, 7'h00, 8'hAA, dummy);
            #500;
            send_command(CMD_READ, 7'h00, 8'h00, rdata);
            verify_data(8'hAA, rdata, "First address (0x00)");
            #100;
            
            // Test address 0x7F (last)
            send_command(CMD_WREN, 7'h00, 8'h00, dummy);
            #50;
            send_command(CMD_WRITE, 7'h7F, 8'h55, dummy);
            #500;
            send_command(CMD_READ, 7'h7F, 8'h00, rdata);
            verify_data(8'h55, rdata, "Last address (0x7F)");
        end
        
        #200;
        
        // Test 8: Write Status Register
        begin
            reg [7:0] status;
            $display("\n--- Test 8: Write Status Register ---");
            
            // Enable write
            send_command(CMD_WREN, 7'h00, 8'h00, status);
            #100;
            
            // Write status register (set BP bits)
            send_command(CMD_WRSR, 7'h00, 8'h0C, status);
            #500;
            
            // Read back status
            send_command(CMD_RDSR, 7'h00, 8'h00, status);
            verify_data(8'h0C, status, "Status register write");
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


// Behavioral model of AT25010 EEPROM
module at25010_model (
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    output reg miso
);

    // Memory array (128 bytes)
    reg [7:0] memory [0:127];
    
    // Status register
    reg [7:0] status_reg;
    
    // Internal registers
    reg [7:0] shift_in;
    reg [7:0] shift_out;
    reg [3:0] bit_count;
    reg [7:0] command;
    reg [6:0] address;
    reg [3:0] state;
    
    // State machine
    localparam ST_IDLE    = 4'd0;
    localparam ST_CMD     = 4'd1;
    localparam ST_ADDR    = 4'd2;
    localparam ST_RDDATA  = 4'd3;
    localparam ST_WRDATA  = 4'd4;
    
    // Command opcodes
    localparam OP_WREN  = 8'h06;
    localparam OP_WRDI  = 8'h04;
    localparam OP_RDSR  = 8'h05;
    localparam OP_WRSR  = 8'h01;
    localparam OP_READ  = 8'h03;
    localparam OP_WRITE = 8'h02;
    
    integer i;
    
    initial begin
        for (i = 0; i < 128; i = i + 1) begin
            memory[i] = 8'hFF;
        end
        status_reg = 8'h00;
        miso = 1'b1;
        state = ST_IDLE;
        bit_count = 0;
        shift_in = 0;
        shift_out = 0;
        command = 0;
        address = 0;
    end
    
    reg [7:0] complete_byte;
    
    // Combinational logic to capture complete byte
    always @(*) begin
        complete_byte = {shift_in[6:0], mosi};
    end
    
    // Main SPI logic on rising edge (Mode 0)
    always @(posedge sclk or posedge cs_n) begin
        if (cs_n) begin
            state <= ST_IDLE;
            bit_count <= 0;
            miso <= 1'b1;
            shift_in <= 0;
        end else begin
            // Shift in MOSI bit
            shift_in <= {shift_in[6:0], mosi};
            bit_count <= bit_count + 1;
            
            // Process complete byte
            if (bit_count == 7) begin
                bit_count <= 0;
                
                case (state)
                    ST_IDLE: begin
                        // First byte is command
                        command <= complete_byte;
                        
                        case (complete_byte)
                            OP_WREN: begin
                                status_reg[1] <= 1'b1;  // Set WEL
                            end
                            
                            OP_WRDI: begin
                                status_reg[1] <= 1'b0;  // Clear WEL
                            end
                            
                            OP_RDSR: begin
                                shift_out <= status_reg;
                                state <= ST_RDDATA;
                            end
                            
                            OP_WRSR: begin
                                state <= ST_WRDATA;
                            end
                            
                            OP_READ, OP_WRITE: begin
                                state <= ST_CMD;
                            end
                        endcase
                    end
                    
                    ST_CMD: begin
                        // Second byte is address
                        address <= complete_byte[6:0];
                        
                        if (command == OP_READ) begin
                            shift_out <= memory[complete_byte[6:0]];
                            state <= ST_RDDATA;
                        end else if (command == OP_WRITE) begin
                            state <= ST_ADDR;
                        end
                    end
                    
                    ST_ADDR: begin
                        if (command == OP_WRITE && status_reg[1]) begin
                            memory[address] <= complete_byte;
                            status_reg[1] <= 1'b0;  // Clear WEL
                        end
                        state <= ST_IDLE;
                    end
                    
                    ST_RDDATA: begin
                        if (command == OP_READ) begin
                            address <= address + 1;
                            shift_out <= memory[address + 1];
                        end
                    end
                    
                    ST_WRDATA: begin
                        if (command == OP_WRSR && status_reg[1]) begin
                            status_reg <= complete_byte & 8'h0F;
                            status_reg[1] <= 1'b0;
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
