module at25010_if (
    input  logic clk,
    input  logic rst_n,

    // Request to read 1 byte key
    input  logic        req_read,
    input  logic [7:0]  addr,
    output logic [7:0]  data,
    output logic        data_valid,
    output logic        busy,

    // SPI
    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_CMD,     // send READ command
        S_ADDR,    // send address byte
        S_DATA,    // receive data byte
        S_DONE
    } state_t;

    state_t state, next;

    logic spi_start, spi_done, last_byte;
    logic [7:0] tx, rx;

    spi_master spi (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .tx_data(tx),
        .rx_data(rx),
        .last_byte(last_byte),
        .busy(),
        .done(spi_done),
        .sck(sck),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next;
    end

    assign busy = (state != S_IDLE);
    assign data_valid = (state == S_DONE);

    always_comb begin
        spi_start = 0;
        last_byte = 0;
        tx = 8'h00;

        next = state;

        case (state)
            S_IDLE:
                if (req_read)
                    next = S_CMD;

            S_CMD: begin
                spi_start = 1;
                tx = 8'h03;      // READ opcode
                next = S_ADDR;
            end

            S_ADDR: begin
                if (spi_done) begin
                    spi_start = 1;
                    tx = addr;
                    next = S_DATA;
                end
            end

            S_DATA: begin
                if (spi_done) begin
                    spi_start = 1;
                    tx = 8'h00;         // dummy byte
                    last_byte = 1;
                    next = S_DONE;
                end
            end

            S_DONE:
                next = S_IDLE;
        endcase
    end

    assign data = rx;

endmodule
