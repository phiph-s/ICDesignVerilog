// SPI Master Module
// Supports SPI Mode 0 (CPOL=0, CPHA=0) and Mode 3 (CPOL=1, CPHA=1)
// Configurable clock divider for SPI clock generation

module spi_master #(
    parameter CLOCK_DIV = 4  // System clock divider for SPI clock (must be even, >= 4)
)(
    input wire clk,           // System clock
    input wire rst_n,         // Active low reset
    
    // Control interface
    input wire start,         // Start SPI transaction
    input wire [7:0] tx_data, // Data to transmit
    output reg [7:0] rx_data, // Data received
    output reg busy,          // Transaction in progress
    output reg done,          // Transaction complete (pulse)
    
    // SPI configuration
    input wire cpol,          // Clock polarity (0 or 1)
    input wire cpha,          // Clock phase (0 or 1)
    
    // SPI interface
    output reg spi_sclk,      // SPI clock
    output reg spi_mosi,      // Master Out Slave In
    input wire spi_miso       // Master In Slave Out
);

    // Internal registers
    reg [7:0] shift_reg_tx;
    reg [7:0] shift_reg_rx;
    reg [2:0] bit_counter;
    reg [7:0] clk_counter;
    reg [2:0] state;
    
    // State machine
    localparam IDLE     = 3'b000;
    localparam START    = 3'b001;
    localparam CLOCK_LO = 3'b010;
    localparam CLOCK_HI = 3'b011;
    localparam FINISH   = 3'b100;
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            spi_mosi <= 0;
            spi_sclk <= 0;
            shift_reg_tx <= 0;
            shift_reg_rx <= 0;
            rx_data <= 0;
            bit_counter <= 0;
            clk_counter <= 0;
        end else begin
            done <= 0;  // Done is a pulse
            
            case (state)
                IDLE: begin
                    busy <= 0;
                    spi_sclk <= cpol;
                    bit_counter <= 0;
                    clk_counter <= 0;
                    
                    if (start) begin
                        busy <= 1;
                        shift_reg_tx <= tx_data;
                        shift_reg_rx <= 0;
                        
                        if (cpha == 0) begin
                            // Mode 0/2: Set first data bit before clock
                            spi_mosi <= tx_data[7];
                        end
                        
                        state <= START;
                    end
                end
                
                START: begin
                    // Small delay before starting clock
                    if (clk_counter >= (CLOCK_DIV >> 2)) begin
                        clk_counter <= 0;
                        if (cpha == 0) begin
                            // Mode 0: Sample first bit before first clock edge
                            shift_reg_rx <= {shift_reg_rx[6:0], spi_miso};
                            state <= CLOCK_HI;
                        end else begin
                            state <= CLOCK_LO;
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                
                CLOCK_LO: begin
                    spi_sclk <= cpol ? 1'b1 : 1'b0;
                    
                    if (clk_counter >= (CLOCK_DIV >> 1) - 1) begin
                        clk_counter <= 0;
                        
                        if (cpha == 0) begin
                            // Mode 0/2: Sample on first edge (rising if cpol=0)
                            shift_reg_rx <= {shift_reg_rx[6:0], spi_miso};
                        end else begin
                            // Mode 1/3: Shift on first edge
                            spi_mosi <= shift_reg_tx[7];
                            shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                        end
                        
                        state <= CLOCK_HI;
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                
                CLOCK_HI: begin
                    spi_sclk <= cpol ? 1'b0 : 1'b1;
                    
                    if (clk_counter >= (CLOCK_DIV >> 1) - 1) begin
                        clk_counter <= 0;
                        
                        if (cpha == 0) begin
                            // Mode 0/2: Shift on second edge
                            bit_counter <= bit_counter + 1;
                            if (bit_counter < 7) begin
                                spi_mosi <= shift_reg_tx[6];  // Output BEFORE shift
                                shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                                state <= CLOCK_LO;
                            end else begin
                                state <= FINISH;
                            end
                        end else begin
                            // Mode 1/3: Sample on second edge
                            shift_reg_rx <= {shift_reg_rx[6:0], spi_miso};
                            bit_counter <= bit_counter + 1;
                            
                            if (bit_counter < 7) begin
                                state <= CLOCK_LO;
                            end else begin
                                state <= FINISH;
                            end
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                
                FINISH: begin
                    spi_sclk <= cpol;
                    rx_data <= shift_reg_rx;
                    done <= 1;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
