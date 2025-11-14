// MFRC522 RFID Reader Interface Module
// Supports register read/write and FIFO operations
// SPI Mode 0 (CPOL=0, CPHA=0)

module mfrc522_interface #(
    parameter CLOCK_DIV = 4  // SPI clock divider
)(
    input wire clk,
    input wire rst_n,
    
    // Command interface
    input wire cmd_valid,           // Command valid
    output reg cmd_ready,           // Ready for command
    input wire cmd_is_write,        // 1=write, 0=read
    input wire [5:0] cmd_addr,      // Register address (6 bits)
    input wire [7:0] cmd_wdata,     // Write data
    output reg [7:0] cmd_rdata,     // Read data
    output reg cmd_done,            // Command complete
    
    // SPI interface
    output wire spi_cs_n,           // Chip select (active low)
    output wire spi_sclk,           // SPI clock
    output wire spi_mosi,           // Master out slave in
    input wire spi_miso             // Master in slave out
);

    // MFRC522 SPI Protocol:
    // Byte 0: Address byte
    //   Bit 7: 0=read, 1=write
    //   Bit 6-1: Address (6 bits)
    //   Bit 0: Always 0
    // Byte 1: Data byte (write) or dummy+data (read)
    
    // State machine
    localparam ST_IDLE      = 3'b000;
    localparam ST_CS_SETUP  = 3'b001;
    localparam ST_SEND_ADDR = 3'b010;
    localparam ST_SEND_DATA = 3'b011;
    localparam ST_RECV_DATA = 3'b100;
    localparam ST_CS_HOLD   = 3'b101;
    localparam ST_DONE      = 3'b110;
    
    reg [2:0] state;
    reg current_is_write;
    reg [5:0] current_addr;
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
    
    // SPI Master instance
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
            cmd_rdata <= 0;
            cs_active <= 0;
            spi_start <= 0;
            spi_tx_data <= 0;
            current_is_write <= 0;
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
                        current_is_write <= cmd_is_write;
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
                        state <= ST_SEND_ADDR;
                        
                        // Build address byte: [R/W][A5:A0][0]
                        spi_tx_data <= {current_is_write, current_addr, 1'b0};
                        spi_start <= 1;
                    end else begin
                        timing_counter <= timing_counter + 1;
                    end
                end
                
                ST_SEND_ADDR: begin
                    if (spi_done) begin
                        if (current_is_write) begin
                            // Send write data
                            spi_tx_data <= current_wdata;
                            spi_start <= 1;
                            state <= ST_SEND_DATA;
                        end else begin
                            // Receive read data (send dummy byte)
                            spi_tx_data <= 8'h00;
                            spi_start <= 1;
                            state <= ST_RECV_DATA;
                        end
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
                
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
