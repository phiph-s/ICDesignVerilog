module at25010_if (
    input  logic       clk,
    input  logic       rst_n,

    // User request
    input  logic       req_read,
    input  logic [7:0] addr,
    output logic [7:0] data,
    output logic       data_valid,   // 1 Takt lang, wenn data gültig
    output logic       busy,         // Modul beschäftigt

    // SPI pins
    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    // ------------------------------------------------------------
    // Verbindung zum SPI-Master
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
    // FSM: READ-Sequenz: 0x03 → addr → dummy
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_CMD_START,
        S_CMD_WAIT,
        S_ADDR_START,
        S_ADDR_WAIT,
        S_DATA_START,
        S_DATA_WAIT
    } state_t;

    state_t state;

    assign busy = (state != S_IDLE);

    // FSM + Steuersignale
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            spi_start   <= 1'b0;
            spi_last_byte <= 1'b0;
            spi_tx_data <= 8'h00;
            data        <= 8'h00;
            data_valid  <= 1'b0;
        end else begin
            // Defaults pro Takt
            spi_start   <= 1'b0;
            data_valid  <= 1'b0;

            case (state)

                // ------------------------------------------------
                S_IDLE: begin
                    if (req_read) begin
                        state <= S_CMD_START;
                    end
                end

                // ------------------------------------------------
                // 1) READ-Opcode senden (0x03)
                // ------------------------------------------------
                S_CMD_START: begin
                    spi_tx_data   <= 8'h03;   // READ opcode
                    spi_last_byte <= 1'b0;   // weitere Bytes folgen
                    spi_start     <= 1'b1;   // 1-Takt-Startpuls
                    state         <= S_CMD_WAIT;
                end

                S_CMD_WAIT: begin
                    if (spi_done) begin
                        state <= S_ADDR_START;
                    end
                end

                // ------------------------------------------------
                // 2) Adresse senden
                // ------------------------------------------------
                S_ADDR_START: begin
                    spi_tx_data   <= addr;
                    spi_last_byte <= 1'b0;   // noch nicht letztes Byte
                    spi_start     <= 1'b1;
                    state         <= S_ADDR_WAIT;
                end

                S_ADDR_WAIT: begin
                    if (spi_done) begin
                        state <= S_DATA_START;
                    end
                end

                // ------------------------------------------------
                // 3) Dummy-Byte senden, dabei Daten empfangen
                // ------------------------------------------------
                S_DATA_START: begin
                    spi_tx_data   <= 8'h00;  // Dummy
                    spi_last_byte <= 1'b1;   // letztes Byte der Transaktion
                    spi_start     <= 1'b1;
                    state         <= S_DATA_WAIT;
                end

                S_DATA_WAIT: begin
                    if (spi_done) begin
                        data       <= spi_rx_data;
                        data_valid <= 1'b1;   // ein Takt gültig
                        state      <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
