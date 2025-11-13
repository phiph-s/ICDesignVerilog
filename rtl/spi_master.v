// spi_master.sv - MODE 0 SPI MASTER WITH MULTI-BYTE SUPPORT

module spi_master #(
    parameter CLK_DIV = 4
)(
    input  logic clk,
    input  logic rst_n,

    // control
    input  logic       start,        // begin sending this byte
    input  logic       last_byte,    // 1 = this is the final byte of this transaction
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,

    output logic busy,               // high when shifting or waiting for next byte
    output logic done,               // one-cycle pulse when THIS byte is complete

    // SPI pins
    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    typedef enum logic [1:0] {
        S_IDLE  = 2'd0,
        S_SHIFT = 2'd1,
        S_DONE  = 2'd2
    } state_t;

    state_t state;

    logic [7:0] tx_shift, rx_shift;
    logic [2:0] bit_cnt;
    logic [15:0] div_cnt;

    assign busy = (state != S_IDLE);

    // --------------------------------------------------------
    // Main FSM
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            sck      <= 0;
            cs_n     <= 1;
            done     <= 0;
            bit_cnt  <= 0;
            div_cnt  <= 0;
            mosi     <= 0;
            rx_data  <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
        end else begin
            done <= 0;

            case (state)

                // ----------------------------------------------------
                // IDLE
                // ----------------------------------------------------
                S_IDLE: begin
                    sck <= 0;

                    if (start) begin
                        // If CS was high, this starts a new transaction
                        if (cs_n == 1)
                            cs_n <= 0;

                        tx_shift <= tx_data;
                        rx_shift <= 0;
                        bit_cnt  <= 7;
                        div_cnt  <= 0;

                        // *** IMPORTANT: preload MOSI with MSB BEFORE first rising edge
                        mosi     <= tx_data[7];

                        state    <= S_SHIFT;
                    end
                end

                // ----------------------------------------------------
                // SHIFT 8 BITS
                // ----------------------------------------------------
                S_SHIFT: begin
                    if (div_cnt == (CLK_DIV/2 - 1)) begin
                        div_cnt <= 0;

                        // toggle SCK
                        sck <= ~sck;

                        // RISING edge (old sck == 0): sample MISO
                        if (sck == 0) begin
                            rx_shift <= {rx_shift[6:0], miso};

                            if (bit_cnt == 0) begin
                                state <= S_DONE;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end

                        // FALLING edge (old sck == 1): shift out next MOSI bit
                        if (sck == 1) begin
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            mosi     <= tx_shift[6];  // next MSB after shift
                        end

                    end else begin
                        div_cnt <= div_cnt + 1;
                    end
                end

                // ----------------------------------------------------
                // DONE WITH ONE BYTE
                // ----------------------------------------------------
                S_DONE: begin
                    sck     <= 0;
                    rx_data <= rx_shift;
                    done    <= 1;

                    if (last_byte) begin
                        // End full SPI transaction
                        cs_n  <= 1;
                        state <= S_IDLE;
                    end else begin
                        // Keep CS LOW: wait here for next byte (next start pulse)
                        if (start) begin
                            tx_shift <= tx_data;
                            rx_shift <= 0;
                            bit_cnt  <= 7;
                            div_cnt  <= 0;

                            // preload MOSI for next byte
                            mosi     <= tx_data[7];

                            state    <= S_SHIFT;
                        end
                    end
                end

            endcase
        end
    end

endmodule
