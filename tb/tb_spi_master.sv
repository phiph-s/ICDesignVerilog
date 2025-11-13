// tb_spi_master.sv
`timescale 1ns/1ps

module tb_spi_master;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n = 0;
    initial begin
        #20 rst_n = 1;
    end

    // DUT wires
    logic start;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic busy, done;

    logic sck, mosi, miso, cs_n;

    spi_master #(.CLK_DIV(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .busy(busy),
        .done(done),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_slave_dummy slave (
        .sck(sck),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso)
    );

    // Test logic
    initial begin
        start = 0;
        tx_data = 8'h3C;

        @(posedge rst_n);
        @(posedge clk);

        $display("[TB] starting SPI transaction");
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        $display("[TB] DONE, rx=%02h", rx_data);

        if (rx_data !== 8'hA5)
            $error("Expected A5, got %02h", rx_data);

        $display("[TB] Test passed!");
        #50 $finish;
    end

endmodule
