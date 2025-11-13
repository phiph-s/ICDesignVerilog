// tb/spi_slave_dummy.v
// Very simple SPI mode 0 slave that always returns 0xA5

module spi_slave_dummy(
    input  sck,
    input  cs_n,
    input  mosi,
    output reg miso
);

    reg [7:0] tx;
    reg [7:0] rx;
    reg [2:0] bit_cnt;

    initial begin
        tx      = 8'hA5;
        rx      = 8'h00;
        bit_cnt = 3'd7;
        miso    = 1'b0;
    end

    // Start of transaction: CS goes low
    always @(negedge cs_n) begin
        tx      <= 8'hA5;   // constant response
        bit_cnt <= 3'd7;
        miso    <= tx[7];   // drive MSB immediately (FIXED)
    end

    // Sample MOSI on rising edge (mode 0)
    always @(posedge sck) begin
        if (!cs_n) begin
            rx[bit_cnt] <= mosi;
        end
    end

    // Drive next MISO bit on falling edge
    always @(negedge sck) begin
        if (!cs_n) begin
            if (bit_cnt != 0) begin
                bit_cnt <= bit_cnt - 1;
                miso    <= tx[bit_cnt-1];
            end
        end
    end

endmodule
