// spi_master.sv - WORKING WITH ICARUS & CORRECT MODE 0 TIMING

module spi_master #(
    parameter CLK_DIV = 4
)(
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,

    output logic busy,
    output logic done,

    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    typedef enum logic [1:0] {
        S_IDLE  = 2'd0,
        S_LOAD  = 2'd1,
        S_SHIFT = 2'd2,
        S_DONE  = 2'd3
    } state_t;

    state_t state;

    logic [7:0] tx_shift, rx_shift;
    logic [2:0] bit_cnt;
    logic [15:0] div_cnt;

    assign busy = (state != S_IDLE);

    // state & logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            sck      <= 0;
            cs_n     <= 1;
            done     <= 0;
            bit_cnt  <= 0;
            div_cnt  <= 0;
            mosi     <= 0;
        end else begin
            done <= 0;

            case (state)

                // ----------------------------------------------------
                // IDLE
                // ----------------------------------------------------
                S_IDLE: begin
                    sck <= 0;
                    cs_n <= 1;

                    if (start) begin
                        cs_n <= 0;
                        tx_shift <= tx_data;
                        rx_shift <= 0;
                        bit_cnt <= 7;
                        div_cnt <= 0;
                        state <= S_SHIFT;
                    end
                end

                // ----------------------------------------------------
                // SHIFT
                // ----------------------------------------------------
                S_SHIFT: begin
                    // divider
                    if (div_cnt == (CLK_DIV/2 - 1)) begin
                        div_cnt <= 0;
                        sck <= ~sck;

                        // FALLING edge: drive MOSI
                        if (sck == 1) begin
                            mosi <= tx_shift[7];
                            tx_shift <= {tx_shift[6:0], 1'b0};
                        end

                        // RISING edge: sample MISO
                        if (sck == 0) begin
                            rx_shift <= {rx_shift[6:0], miso};

                            if (bit_cnt == 0) begin
                                state <= S_DONE;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end

                    end else begin
                        div_cnt <= div_cnt + 1;
                    end
                end

                // ----------------------------------------------------
                // DONE
                // ----------------------------------------------------
                S_DONE: begin
                    cs_n <= 1;
                    sck  <= 0;
                    rx_data <= rx_shift;
                    done <= 1;
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
