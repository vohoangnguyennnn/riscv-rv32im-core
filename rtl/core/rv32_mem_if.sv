interface rv32_mem_if;

  // Request channel: master to slave. Addresses are byte addresses; the core
  // drives word-aligned bus requests and uses byte strobes for sub-word stores.
  logic        req_valid;
  logic        req_ready;
  logic [31:0] req_addr;
  logic        req_write;
  logic [31:0] req_wdata;
  logic [3:0]  req_wstrb;

  // Response channel: slave to master. Stores also receive a response so an
  // access fault is architecturally known before retirement.
  logic        rsp_valid;
  logic [31:0] rsp_rdata;
  logic        rsp_err;

  modport master (
    output req_valid,
    output req_addr,
    output req_write,
    output req_wdata,
    output req_wstrb,
    input  req_ready,
    input  rsp_valid,
    input  rsp_rdata,
    input  rsp_err
  );

  modport slave (
    input  req_valid,
    input  req_addr,
    input  req_write,
    input  req_wdata,
    input  req_wstrb,
    output req_ready,
    output rsp_valid,
    output rsp_rdata,
    output rsp_err
  );

endinterface
