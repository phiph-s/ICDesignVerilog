`timescale 1ns/1ps

// ------------------------------------------------------------
// Simple behavioral model of AT25010 (SPI slave, READ only)
// ------------------------------------------------------------
module at25010_model (
    input  sck,
    input  cs_n,
    input  mosi,
    output reg miso
);

    reg [7:0] mem [0:255];

    initial begin
        mem[8'h10] = 8'hA5;
        mem[8'h11] = 8'h5A;
        mem[8'h20] = 8'h3C;
    end

    reg [7:0] shift_in;
    reg [7:0] out_byte;
    reg [7:0] cmd;
    reg [7:0] addr;

    integer bit_cnt;

    // start of SPI transaction
    always @(negedge cs_n) begin
        bit_cnt  = 0;
        shift_in = 0;
        miso     = 0;
        cmd      = 0;
        addr     = 0;
        out_byte = 0;
    end

    // sample MOSI on rising edge (MODE 0)
    always @(posedge sck) begin
        if (!cs_n) begin
            shift_in <= {shift_in[6:0], mosi};
            bit_cnt  <= bit_cnt + 1;

            // first byte → command
            if (bit_cnt == 7)
                cmd <= {shift_in[6:0], mosi};

            // second byte → address
            if (bit_cnt == 15) begin
                addr     <= {shift_in[6:0], mosi};
                out_byte <= mem[{shift_in[6:0], mosi}];
            end
        end
    end

    // drive MISO on falling edge (MODE 0)
    always @(negedge sck) begin
        if (!cs_n) begin
            if (bit_cnt >= 16 && bit_cnt < 24)
                miso <= out_byte[7 - (bit_cnt - 16)];
            else
                miso <= 0;
        end else begin
            miso <= 0;
        end
    end

endmodule



// ------------------------------------------------------------
// Testbench for at25010_if
// ------------------------------------------------------------
module tb_at25010_if;

    reg clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    reg rst_n = 0;

    reg        req_read;
    reg [7:0]  addr;
    wire [7:0] data;
    wire       data_valid;
    wire       busy;

    wire sck, mosi, miso, cs_n;

    // DUT
    at25010_if dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_read  (req_read),
        .addr      (addr),
        .data      (data),
        .data_valid(data_valid),
        .busy      (busy),
        .sck       (sck),
        .mosi      (mosi),
        .miso      (miso),
        .cs_n      (cs_n)
    );

    // EEPROM model
    at25010_model mem (
        .sck  (sck),
        .cs_n (cs_n),
        .mosi (mosi),
        .miso (miso)
    );

    initial begin
        $dumpfile("at25010_if.vcd");
        $dumpvars(0, tb_at25010_if);

        req_read = 0;
        addr     = 8'h00;

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        $display("[%0t] Release reset", $time);

        repeat (5) @(posedge clk);

        // Read 0x10
        addr     = 8'h10;
        req_read = 1;
        @(posedge clk);
        req_read = 0;
        $display("[%0t] Request read from 0x%02h", $time, addr);
        wait (data_valid);
        $display("[%0t] Read complete: addr=0x%02h data=0x%02h", $time, addr, data);

        repeat (10) @(posedge clk);

        // Read 0x11
        addr     = 8'h11;
        req_read = 1;
        @(posedge clk);
        req_read = 0;
        $display("[%0t] Request read from 0x%02h", $time, addr);
        wait (data_valid);
        $display("[%0t] Read complete: addr=0x%02h data=0x%02h", $time, addr, data);

        repeat (10) @(posedge clk);
        $finish;
    end

endmodule