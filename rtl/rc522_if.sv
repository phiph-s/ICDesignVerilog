module rc522_if (
    input  logic clk,
    input  logic rst_n,

    // Simple register API
    input  logic        req_read,
    input  logic        req_write,
    input  logic [7:0]  addr,
    input  logic [7:0]  wr_data,
    output logic [7:0]  rd_data,
    output logic        data_valid,
    output logic        busy,

    // SPI
    output logic sck,
    output logic mosi,
    input  logic miso,
    output logic cs_n
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_WRITE,
        S_READ_ADDR,
        S_READ_DATA
    } state_t;

    state_t state, next;

    logic spi_start, spi_done;
    logic [7:0] tx, rx;

    spi_master spi (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .tx_data(tx),
        .rx_data(rx),
        .last_byte(1'b0),
        .busy(),
        .done(spi_done),
        .sck(sck),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n)
    );

    assign busy = (state != S_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next;
    end

    always_comb begin
        spi_start = 0;
        data_valid = 0;
        tx = 8'h00;
        next = state;

        case (state)
            S_IDLE:
                if (req_write)
                    next = S_WRITE;
                else if (req_read)
                    next = S_READ_ADDR;

            S_WRITE: begin
                // addr | 0x00 : RC522 write
                spi_start = 1;
                tx = {addr[6:0], 1'b0};
                if (spi_done)
                    next = S_READ_DATA;
            end

            S_READ_ADDR: begin
                // addr | 0x80 : RC522 read
                spi_start = 1;
                tx = {addr[6:0], 1'b1};
                if (spi_done)
                    next = S_READ_DATA;
            end

            S_READ_DATA: begin
                spi_start = 1;
                tx = wr_data; // ignored for read
                if (spi_done) begin
                    data_valid = 1;
                    rd_data = rx;
                    next = S_IDLE;
                end
            end
        endcase
    end

endmodule
