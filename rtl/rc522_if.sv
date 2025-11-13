module rc522_if (
    input  logic       clk,
    input  logic       rst_n,

    // User API
    input  logic       req_write,
    input  logic       req_read,
    input  logic [7:0] addr,
    input  logic [7:0] wr_data,
    output logic [7:0] rd_data,
    output logic       data_valid,   // high 1 cycle when write/read is done
    output logic       busy,

    // SPI pins
    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    // ------------------------------------------------------------
    // SPI master connection
    // ------------------------------------------------------------
    logic       spi_start;
    logic       spi_last_byte;
    logic [7:0] spi_tx_data;
    logic [7:0] spi_rx_data;
    logic       spi_busy;
    logic       spi_done;

    spi_master #(
        .CLK_DIV(4)
    ) spi_inst (
        .clk      (clk),
        .rst_n    (rst_n),

        .start    (spi_start),
        .last_byte(spi_last_byte),
        .tx_data  (spi_tx_data),
        .rx_data  (spi_rx_data),

        .busy     (spi_busy),
        .done     (spi_done),

        .sck      (sck),
        .mosi     (mosi),
        .miso     (miso),
        .cs_n     (cs_n)
    );

    // ------------------------------------------------------------
    // FSM für 2-Byte-Transaktion: ADDR → DATA
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_ADDR_START,
        S_ADDR_WAIT,
        S_DATA_START,
        S_DATA_WAIT
    } state_t;

    state_t state;
    logic   is_read;  // 1 = read, 0 = write

    assign busy = (state != S_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            spi_start   <= 1'b0;
            spi_last_byte <= 1'b0;
            spi_tx_data <= 8'h00;
            rd_data     <= 8'h00;
            data_valid  <= 1'b0;
            is_read     <= 1'b0;
        end else begin
            // Defaults
            spi_start  <= 1'b0;
            data_valid <= 1'b0;

            case (state)

                // ------------------------------------------------
                S_IDLE: begin
                    if (req_write && !req_read) begin
                        is_read <= 1'b0;
                        state   <= S_ADDR_START;
                    end else if (req_read && !req_write) begin
                        is_read <= 1'b1;
                        state   <= S_ADDR_START;
                    end
                end

                // ------------------------------------------------
                // 1) Adress-Byte mit R/W-Bit senden
                // ------------------------------------------------
                S_ADDR_START: begin
                    spi_tx_data   <= {addr[6:0], is_read ? 1'b1 : 1'b0};
                    spi_last_byte <= 1'b0;  // noch ein Byte folgt
                    spi_start     <= 1'b1;
                    state         <= S_ADDR_WAIT;
                end

                S_ADDR_WAIT: begin
                    if (spi_done) begin
                        state <= S_DATA_START;
                    end
                end

                // ------------------------------------------------
                // 2) Datenbyte (Write) oder Dummy (Read)
                // ------------------------------------------------
                S_DATA_START: begin
                    spi_tx_data   <= is_read ? 8'h00 : wr_data;
                    spi_last_byte <= 1'b1;  // letztes Byte
                    spi_start     <= 1'b1;
                    state         <= S_DATA_WAIT;
                end

                S_DATA_WAIT: begin
                    if (spi_done) begin
                        if (is_read) begin
                            rd_data <= spi_rx_data;
                        end
                        data_valid <= 1'b1;   // Operation fertig
                        state      <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
