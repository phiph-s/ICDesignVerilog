// AT25010 EEPROM Interface Module
// 1Kbit (128 x 8) SPI Serial EEPROM
// Supports standard AT25010 command set

module at25010_interface #(
    parameter CLOCK_DIV = 4  // SPI clock divider
)(
    input wire clk,
    input wire rst_n,
    
    // Command interface
    input wire cmd_valid,           // Command valid
    output reg cmd_ready,           // Ready for command
    input wire [2:0] cmd_type,      // Command type
    input wire [6:0] cmd_addr,      // Address (7 bits for 128 bytes)
    input wire [7:0] cmd_wdata,     // Write data
    output reg [7:0] cmd_rdata,     // Read data
    output reg cmd_done,            // Command complete
    output reg cmd_error,           // Command error
    
    // SPI interface
    output wire spi_cs_n,           // Chip select (active low)
    output wire spi_sclk,           // SPI clock
    output wire spi_mosi,           // Master out slave in
    input wire spi_miso             // Master in slave out
);

    // Command types
    localparam CMD_WREN  = 3'b000;  // Write Enable
    localparam CMD_WRDI  = 3'b001;  // Write Disable
    localparam CMD_RDSR  = 3'b010;  // Read Status Register
    localparam CMD_WRSR  = 3'b011;  // Write Status Register
    localparam CMD_READ  = 3'b100;  // Read Data
    localparam CMD_WRITE = 3'b101;  // Write Data
    
    // AT25010 instruction opcodes
    localparam OP_WREN  = 8'h06;
    localparam OP_WRDI  = 8'h04;
    localparam OP_RDSR  = 8'h05;
    localparam OP_WRSR  = 8'h01;
    localparam OP_READ  = 8'h03;
    localparam OP_WRITE = 8'h02;
    
    // State machine
    localparam ST_IDLE      = 4'b0000;
    localparam ST_CS_SETUP  = 4'b0001;
    localparam ST_SEND_CMD  = 4'b0010;
    localparam ST_SEND_ADDR = 4'b0011;
    localparam ST_SEND_DATA = 4'b0100;
    localparam ST_RECV_DATA = 4'b0101;
    localparam ST_CS_HOLD   = 4'b0110;
    localparam ST_DONE      = 4'b0111;
    localparam ST_ERROR     = 4'b1000;
    
    reg [3:0] state;
    reg [2:0] current_cmd;
    reg [6:0] current_addr;
    reg [7:0] current_wdata;
    
    // SPI Master signals
    reg spi_start;
    reg [7:0] spi_tx_data;
    wire [7:0] spi_rx_data;
    wire spi_busy;
    wire spi_done;
    
    // Chip select control
    reg cs_active;
    assign spi_cs_n = ~cs_active;
    
    // Timing counter for CS setup/hold
    reg [3:0] timing_counter;
    
    // SPI Master instance (Mode 0: CPOL=0, CPHA=0)
    spi_master #(
        .CLOCK_DIV(CLOCK_DIV)
    ) spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .tx_data(spi_tx_data),
        .rx_data(spi_rx_data),
        .busy(spi_busy),
        .done(spi_done),
        .cpol(1'b0),           // Mode 0
        .cpha(1'b0),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cmd_ready <= 1;
            cmd_done <= 0;
            cmd_error <= 0;
            cmd_rdata <= 0;
            cs_active <= 0;
            spi_start <= 0;
            spi_tx_data <= 0;
            current_cmd <= 0;
            current_addr <= 0;
            current_wdata <= 0;
            timing_counter <= 0;
        end else begin
            // Default: clear pulses
            cmd_done <= 0;
            spi_start <= 0;
            
            case (state)
                ST_IDLE: begin
                    cmd_ready <= 1;
                    cs_active <= 0;
                    
                    if (cmd_valid && cmd_ready) begin
                        cmd_ready <= 0;
                        current_cmd <= cmd_type;
                        current_addr <= cmd_addr;
                        current_wdata <= cmd_wdata;
                        timing_counter <= 0;
                        state <= ST_CS_SETUP;
                    end
                end
                
                ST_CS_SETUP: begin
                    // CS setup time (2 cycles minimum)
                    if (timing_counter == 0) begin
                        cs_active <= 1;
                        timing_counter <= timing_counter + 1;
                    end else if (timing_counter >= 2) begin
                        timing_counter <= 0;
                        state <= ST_SEND_CMD;
                        
                        // Load opcode based on command
                        case (current_cmd)
                            CMD_WREN:  spi_tx_data <= OP_WREN;
                            CMD_WRDI:  spi_tx_data <= OP_WRDI;
                            CMD_RDSR:  spi_tx_data <= OP_RDSR;
                            CMD_WRSR:  spi_tx_data <= OP_WRSR;
                            CMD_READ:  spi_tx_data <= OP_READ;
                            CMD_WRITE: spi_tx_data <= OP_WRITE;
                            default:   spi_tx_data <= 8'h00;
                        endcase
                        spi_start <= 1;
                    end else begin
                        timing_counter <= timing_counter + 1;
                    end
                end
                
                ST_SEND_CMD: begin
                    if (spi_done) begin
                        // Check if command needs address
                        case (current_cmd)
                            CMD_READ, CMD_WRITE: begin
                                // Send address byte
                                spi_tx_data <= {1'b0, current_addr};
                                spi_start <= 1;
                                state <= ST_SEND_ADDR;
                            end
                            
                            CMD_WRSR: begin
                                // Send data byte for write status
                                spi_tx_data <= current_wdata;
                                spi_start <= 1;
                                state <= ST_SEND_DATA;
                            end
                            
                            CMD_RDSR: begin
                                // Receive status byte
                                spi_tx_data <= 8'h00;  // Dummy data
                                spi_start <= 1;
                                state <= ST_RECV_DATA;
                            end
                            
                            default: begin
                                // Commands without data (WREN, WRDI)
                                state <= ST_CS_HOLD;
                            end
                        endcase
                    end
                end
                
                ST_SEND_ADDR: begin
                    if (spi_done) begin
                        case (current_cmd)
                            CMD_WRITE: begin
                                // Send write data
                                spi_tx_data <= current_wdata;
                                spi_start <= 1;
                                state <= ST_SEND_DATA;
                            end
                            
                            CMD_READ: begin
                                // Receive read data
                                spi_tx_data <= 8'h00;  // Dummy data
                                spi_start <= 1;
                                state <= ST_RECV_DATA;
                            end
                            
                            default: begin
                                state <= ST_ERROR;
                            end
                        endcase
                    end
                end
                
                ST_SEND_DATA: begin
                    if (spi_done) begin
                        state <= ST_CS_HOLD;
                    end
                end
                
                ST_RECV_DATA: begin
                    if (spi_done) begin
                        cmd_rdata <= spi_rx_data;
                        state <= ST_CS_HOLD;
                    end
                end
                
                ST_CS_HOLD: begin
                    // CS hold time (2 cycles minimum)
                    if (timing_counter >= 2) begin
                        cs_active <= 0;
                        timing_counter <= 0;
                        state <= ST_DONE;
                    end else begin
                        timing_counter <= timing_counter + 1;
                    end
                end
                
                ST_DONE: begin
                    cmd_done <= 1;
                    state <= ST_IDLE;
                end
                
                ST_ERROR: begin
                    cmd_error <= 1;
                    cs_active <= 0;
                    state <= ST_IDLE;
                end
                
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
