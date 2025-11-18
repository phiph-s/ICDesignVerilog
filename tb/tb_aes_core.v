`timescale 1ns/1ps

module tb_aes_core;

  logic         clk;
  logic         rst_n;
  logic         start;
  logic         mode;
  logic [127:0] key;
  logic [127:0] plaintext;
  logic [127:0] ciphertext;
  logic         done;

  // Expected result from NIST AES Known Answer Test
  logic [127:0] expected;

  // DUT
  aes_core dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (start),
    .mode      (mode),
    .key       (key),
    .block_in  (plaintext),
    .block_out (ciphertext),
    .done      (done)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    // Test vector from NIST FIPS-197 Appendix C
    key       = 128'h000102030405060708090A0B0C0D0E0F;
    plaintext = 128'h00112233445566778899AABBCCDDEEFF;
    expected  = 128'h69C4E0D86A7B0430D8CDB78070B4C55A;
    mode      = 0; // encrypt
    start     = 0;
    rst_n     = 0;

    // Reset
    #20;
    rst_n = 1;
    #10;

    // Start encryption
    start = 1;
    #10;
    start = 0;

    // Wait for done
    wait(done);
    #10;

    $display("Ciphertext: %032h", ciphertext);
    if (ciphertext === expected)
      $display("SUCCESS: AES-128 core matches NIST test vector!");
    else begin
      $display("FAIL: Expected %032h", expected);
    end

    $finish;
  end

endmodule
