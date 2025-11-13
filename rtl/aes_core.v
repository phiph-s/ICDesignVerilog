module aes_core (
  input  logic [127:0] key,
  input  logic [127:0] block_in,
  output logic [127:0] block_out
);

// instantiate AES-Verilog core
AES_Encrypt u_aes (
  .in       (block_in),
  .key      (key),
  .out      (block_out)
);

endmodule
