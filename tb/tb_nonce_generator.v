`timescale 1ns/1ps

module tb_nonce_generator;

  logic        clk;
  logic        rst_n;
  logic        req;
  logic        valid;
  logic [63:0] nonce;

  // DUT
  nonce_generator dut (
    .clk   (clk),
    .rst_n (rst_n),
    .req   (req),
    .valid (valid),
    .nonce (nonce)
  );

  // 100 MHz clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic request_nonce(input int idx);
    begin
      req = 1'b1;
      @(posedge clk);
      req = 1'b0;

      wait (valid == 1'b1);
      $display("[%0t] NONCE %0d: %016h", $time, idx, nonce);

      @(posedge clk);
    end
  endtask

  initial begin
    req   = 1'b0;
    rst_n = 1'b0;

    // hold reset for 5 cycles
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // wait a bit after reset
    repeat (5) @(posedge clk);

    // generate several nonces
    request_nonce(0);
    request_nonce(1);
    request_nonce(2);
    request_nonce(3);
    request_nonce(4);

    repeat (10) @(posedge clk);
    $display("[%0t] Test finished.", $time);
    $finish;
  end

  initial begin
    $dumpfile("tb_nonce_generator.vcd");
    $dumpvars(0, tb_nonce_generator);
  end

endmodule
