// Blocking load/store unit optimized for the always-ready, one-cycle TCM.
// One compact transaction state also preserves a stable request and drains a
// killed response if a different memory implementation applies backpressure.
module lsu (
  input  logic                     clk_i,
  input  logic                     rst_i,
  input  logic                     kill_i,

  input  logic                     req_valid_i,
  output logic                     req_ready_o,
  input  rv32_pkg::mem_cmd_e       cmd_i,
  input  rv32_pkg::mem_size_e      size_i,
  input  logic                     load_unsigned_i,
  input  logic [31:0]              addr_i,
  input  logic [31:0]              store_data_i,

  rv32_mem_if.master               dmem_m,

  output logic                     rsp_valid_o,
  input  logic                     rsp_ready_i,
  output logic [31:0]              load_data_o,
  output rv32_pkg::exc_t           exception_o,
  output logic [3:0]               trace_wstrb_o,
  output logic [31:0]              trace_wdata_o
);

  import rv32_pkg::*;

  typedef enum logic [1:0] {
    LSU_IDLE,
    LSU_BUSY,
    LSU_RESP
  } lsu_state_e;

  lsu_state_e state_q;

  mem_cmd_e  cmd_q;
  mem_size_e size_q;
  logic      load_unsigned_q;
  word_t     addr_q;
  logic [3:0] store_wstrb_q;
  word_t      store_wdata_q;

  logic request_sent_q;
  logic discard_q;

  word_t load_data_q;
  exc_t  exception_q;

  logic input_is_memory;
  logic input_misaligned;
  logic [3:0] input_store_wstrb;
  word_t input_store_wdata;

  logic issue_input;
  logic issue_saved;
  logic request_fire;
  logic response_seen;
  logic response_discard;
  word_t response_load_data;
  exc_t  response_exception;

  function automatic logic address_misaligned(
    input mem_size_e size,
    input logic [1:0] addr_lsb
  );
    begin
      unique case (size)
        MEM_BYTE: address_misaligned = 1'b0;
        MEM_HALF: address_misaligned = addr_lsb[0];
        MEM_WORD: address_misaligned = |addr_lsb;
        default:  address_misaligned = 1'b1;
      endcase
    end
  endfunction

  function automatic exc_t make_misaligned_exception(
    input mem_cmd_e cmd,
    input word_t    addr
  );
    exc_t result;
    begin
      result       = '0;
      result.valid = 1'b1;
      result.tval  = addr;
      result.cause = (cmd == MEM_LOAD) ? EXC_LOAD_ADDR_MISALIGNED : EXC_STORE_ADDR_MISALIGNED;
      make_misaligned_exception = result;
    end
  endfunction

  function automatic exc_t make_access_exception(
    input mem_cmd_e cmd,
    input word_t    addr,
    input logic     error
  );
    exc_t result;
    begin
      result = '0;
      if (error) begin
        result.valid = 1'b1;
        result.tval  = addr;
        result.cause = (cmd == MEM_LOAD) ? EXC_LOAD_ACCESS_FAULT : EXC_STORE_ACCESS_FAULT;
      end
      make_access_exception = result;
    end
  endfunction

  function automatic word_t extract_load_data(
    input word_t     read_data,
    input logic [1:0] byte_offset,
    input mem_size_e size,
    input logic      load_unsigned
  );
    word_t shifted;
    begin
      shifted = read_data >> {byte_offset, 3'b000};

      unique case (size)
        MEM_BYTE: extract_load_data = load_unsigned ? {24'b0, shifted[7:0]} : {{24{shifted[7]}}, shifted[7:0]};
        MEM_HALF: extract_load_data = load_unsigned ? {16'b0, shifted[15:0]} : {{16{shifted[15]}}, shifted[15:0]};
        MEM_WORD: extract_load_data = shifted;
        default:  extract_load_data = 32'b0;
      endcase
    end
  endfunction

  assign input_is_memory  = (cmd_i == MEM_LOAD) || (cmd_i == MEM_STORE);
  assign input_misaligned = address_misaligned(size_i, addr_i[1:0]);

  // Little-endian store lanes are a shifted byte mask and shifted source data.
  always_comb begin
    unique case (size_i)
      MEM_BYTE: begin
        input_store_wstrb = 4'b0001 << addr_i[1:0];
        input_store_wdata = {24'b0, store_data_i[7:0]} << {addr_i[1:0], 3'b000};
      end
      MEM_HALF: begin
        input_store_wstrb = 4'b0011 << {addr_i[1], 1'b0};
        input_store_wdata = {16'b0, store_data_i[15:0]} << {addr_i[1], 4'b0000};
      end
      MEM_WORD: begin
        input_store_wstrb = 4'b1111;
        input_store_wdata = store_data_i;
      end
      default: begin
        input_store_wstrb = 4'b0000;
        input_store_wdata = 32'b0;
      end
    endcase
  end

  // Keep the request channel independent of the response datapath. Besides
  // making the ready/valid contract explicit, this prevents interconnect
  // address decoding from creating a false combinational-loop dependency in
  // tools that conservatively analyze an entire always_comb process.
  assign req_ready_o = (state_q == LSU_IDLE) && !rst_i && !kill_i;
  assign issue_input = req_valid_i && req_ready_o && input_is_memory && !input_misaligned;
  assign issue_saved = (state_q == LSU_BUSY) && !request_sent_q;

  assign dmem_m.req_valid = issue_input || issue_saved;
  assign dmem_m.req_addr  = issue_input ? {addr_i[31:2], 2'b00} : {addr_q[31:2], 2'b00};
  assign dmem_m.req_write = issue_input ? (cmd_i == MEM_STORE) : (cmd_q == MEM_STORE);
  assign dmem_m.req_wdata = issue_input ? input_store_wdata : store_wdata_q;
  assign dmem_m.req_wstrb = dmem_m.req_write ? (issue_input ? input_store_wstrb : store_wstrb_q) : 4'b0000;

  assign request_fire    = dmem_m.req_valid && dmem_m.req_ready;
  assign response_seen   = dmem_m.rsp_valid && (((state_q == LSU_BUSY) && (request_sent_q || request_fire)) || ((state_q == LSU_IDLE) && request_fire));
  assign response_discard = kill_i || ((state_q == LSU_BUSY) && discard_q);

  always_comb begin
    rsp_valid_o   = 1'b0;
    load_data_o   = 32'b0;
    exception_o   = '0;
    trace_wstrb_o = 4'b0000;
    trace_wdata_o = 32'b0;

    if (state_q == LSU_IDLE) begin
      response_load_data = ((cmd_i == MEM_LOAD) && !dmem_m.rsp_err) ? extract_load_data(dmem_m.rsp_rdata, addr_i[1:0], size_i, load_unsigned_i) : 32'b0;
      response_exception = make_access_exception(cmd_i, addr_i, dmem_m.rsp_err);

      if (issue_input && (cmd_i == MEM_STORE)) begin
        trace_wstrb_o = input_store_wstrb;
        trace_wdata_o = input_store_wdata;
      end
    end else begin
      response_load_data = ((cmd_q == MEM_LOAD) && !dmem_m.rsp_err) ? extract_load_data(dmem_m.rsp_rdata, addr_q[1:0], size_q, load_unsigned_q) : 32'b0;
      response_exception = make_access_exception(cmd_q, addr_q, dmem_m.rsp_err);

      if (cmd_q == MEM_STORE) begin
        trace_wstrb_o = store_wstrb_q;
        trace_wdata_o = store_wdata_q;
      end
    end

    if (state_q == LSU_RESP) begin
      if (!kill_i) begin
        rsp_valid_o = 1'b1;
        load_data_o = load_data_q;
        exception_o = exception_q;
      end
    end else if (response_seen && !response_discard) begin
      rsp_valid_o = 1'b1;
      load_data_o = response_load_data;
      exception_o = response_exception;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q          <= LSU_IDLE;
      cmd_q            <= MEM_NONE;
      size_q           <= MEM_WORD;
      load_unsigned_q  <= 1'b0;
      addr_q           <= 32'b0;
      store_wstrb_q    <= 4'b0000;
      store_wdata_q    <= 32'b0;
      request_sent_q   <= 1'b0;
      discard_q        <= 1'b0;
      load_data_q      <= 32'b0;
      exception_q      <= '0;
    end else begin
      unique case (state_q)
        LSU_IDLE: begin
          discard_q <= 1'b0;

          if (req_valid_i && req_ready_o) begin
            cmd_q           <= cmd_i;
            size_q          <= size_i;
            load_unsigned_q <= load_unsigned_i;
            addr_q          <= addr_i;
            store_wstrb_q   <= ((cmd_i == MEM_STORE) && !input_misaligned) ? input_store_wstrb : 4'b0000;
            store_wdata_q   <= ((cmd_i == MEM_STORE) && !input_misaligned) ? input_store_wdata : 32'b0;
            load_data_q     <= 32'b0;
            exception_q     <= '0;

            if (!input_is_memory || input_misaligned) begin
              if (input_is_memory && input_misaligned) begin
                exception_q <= make_misaligned_exception(cmd_i, addr_i);
              end
              state_q <= LSU_RESP;
            end else if (request_fire && dmem_m.rsp_valid) begin
              if (!rsp_ready_i) begin
                load_data_q <= response_load_data;
                exception_q <= response_exception;
                state_q     <= LSU_RESP;
              end
            end else begin
              request_sent_q <= request_fire;
              state_q        <= LSU_BUSY;
            end
          end
        end

        LSU_BUSY: begin
          if (kill_i) begin
            discard_q <= 1'b1;
          end

          if (request_fire) begin
            request_sent_q <= 1'b1;
          end

          if (response_seen) begin
            request_sent_q <= 1'b0;
            discard_q      <= 1'b0;

            if (response_discard || rsp_ready_i) begin
              state_q <= LSU_IDLE;
            end else begin
              load_data_q <= response_load_data;
              exception_q <= response_exception;
              state_q     <= LSU_RESP;
            end
          end
        end

        LSU_RESP: begin
          if (kill_i || rsp_ready_i) begin
            state_q <= LSU_IDLE;
          end
        end

        default: state_q <= LSU_IDLE;
      endcase
    end
  end

endmodule

