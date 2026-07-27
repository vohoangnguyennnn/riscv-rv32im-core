// Blocking RV32 load/store unit.
//
// The LSU accepts one architectural memory operation at a time. It checks
// alignment before issuing a request, converts sub-word stores into byte
// strobes, aligns every bus request to a 32-bit word, and extracts/sign-extends
// sub-word loads from the returned word. Memory and local-error responses are
// held until the downstream pipeline accepts them.
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

  typedef enum logic [2:0] {
    LSU_IDLE,
    LSU_REQ,
    LSU_WAIT,
    LSU_DROP,
    LSU_RESP
  } lsu_state_e;

  lsu_state_e state_q;

  mem_cmd_e  cmd_q;
  mem_size_e size_q;
  logic      load_unsigned_q;
  word_t     addr_q;
  logic [3:0] store_wstrb_q;
  word_t      store_wdata_q;

  // A request cannot be withdrawn after req_valid has been presented. If the
  // pipeline kills it under request backpressure, complete the handshake and
  // drain the response without exposing it to the pipeline.
  logic discard_q;

  word_t load_data_q;
  exc_t  exception_q;

  logic       input_is_memory;
  logic       input_misaligned;
  logic [3:0] input_store_wstrb;
  word_t      input_store_wdata;

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
        MEM_BYTE: begin
          extract_load_data = load_unsigned ? {24'b0, shifted[7:0]} : {{24{shifted[7]}}, shifted[7:0]};
        end

        MEM_HALF: begin
          extract_load_data = load_unsigned ? {16'b0, shifted[15:0]} : {{16{shifted[15]}}, shifted[15:0]};
        end

        MEM_WORD: extract_load_data = shifted;
        default:  extract_load_data = 32'b0;
      endcase
    end
  endfunction

  assign input_is_memory = (cmd_i == MEM_LOAD) || (cmd_i == MEM_STORE);
  assign input_misaligned = address_misaligned(size_i, addr_i[1:0]);

  // Generate little-endian store lanes from the effective byte address.
  always_comb begin
    input_store_wstrb = 4'b0000;
    input_store_wdata = 32'b0;

    unique case (size_i)
      MEM_BYTE: begin
        unique case (addr_i[1:0])
          2'd0: begin
            input_store_wstrb = 4'b0001;
            input_store_wdata = {24'b0, store_data_i[7:0]};
          end
          2'd1: begin
            input_store_wstrb = 4'b0010;
            input_store_wdata = {16'b0, store_data_i[7:0], 8'b0};
          end
          2'd2: begin
            input_store_wstrb = 4'b0100;
            input_store_wdata = {8'b0, store_data_i[7:0], 16'b0};
          end
          2'd3: begin
            input_store_wstrb = 4'b1000;
            input_store_wdata = {store_data_i[7:0], 24'b0};
          end
          default: ;
        endcase
      end

      MEM_HALF: begin
        if (!addr_i[1]) begin
          input_store_wstrb = 4'b0011;
          input_store_wdata = {16'b0, store_data_i[15:0]};
        end else begin
          input_store_wstrb = 4'b1100;
          input_store_wdata = {store_data_i[15:0], 16'b0};
        end
      end

      MEM_WORD: begin
        input_store_wstrb = 4'b1111;
        input_store_wdata = store_data_i;
      end

      default: ;
    endcase
  end

  always_comb begin
    response_load_data = 32'b0;
    if ((cmd_q == MEM_LOAD) && !dmem_m.rsp_err) begin
      response_load_data = extract_load_data(
        dmem_m.rsp_rdata,
        addr_q[1:0],
        size_q,
        load_unsigned_q
      );
    end

    response_exception = make_access_exception(
      cmd_q,
      addr_q,
      dmem_m.rsp_err
    );
  end

  // Interface outputs are benign unless their corresponding valid is high.
  always_comb begin
    req_ready_o   = 1'b0;
    rsp_valid_o   = 1'b0;
    load_data_o   = 32'b0;
    exception_o   = '0;
    trace_wstrb_o = 4'b0000;
    trace_wdata_o = 32'b0;

    dmem_m.req_valid = 1'b0;
    dmem_m.req_addr  = {addr_q[31:2], 2'b00};
    dmem_m.req_write = (cmd_q == MEM_STORE);
    dmem_m.req_wdata = store_wdata_q;
    dmem_m.req_wstrb = (cmd_q == MEM_STORE) ? store_wstrb_q : 4'b0000;

    unique case (state_q)
      LSU_IDLE: begin
        // Do not accept an operation that is being killed in the same cycle.
        req_ready_o = !kill_i;
      end

      LSU_REQ: begin
        // Once asserted, the request and its payload remain stable until the
        // memory accepts it, even if the pipeline kills the operation.
        dmem_m.req_valid = 1'b1;

        if (cmd_q == MEM_STORE) begin
          trace_wstrb_o = store_wstrb_q;
          trace_wdata_o = store_wdata_q;
        end

        // The project memory contract normally responds no earlier than the
        // acceptance cycle. Supporting a same-cycle response also makes this
        // block safe to reuse with a combinational test slave.
        if (dmem_m.req_ready && dmem_m.rsp_valid && !discard_q && !kill_i) begin
          rsp_valid_o = 1'b1;
          load_data_o = response_load_data;
          exception_o = response_exception;
        end
      end

      LSU_WAIT: begin
        if (cmd_q == MEM_STORE) begin
          trace_wstrb_o = store_wstrb_q;
          trace_wdata_o = store_wdata_q;
        end

        if (dmem_m.rsp_valid && !kill_i) begin
          rsp_valid_o = 1'b1;
          load_data_o = response_load_data;
          exception_o = response_exception;
        end
      end

      LSU_DROP: begin
        // A killed transaction still owns the blocking memory port until its
        // response has been observed and discarded.
      end

      LSU_RESP: begin
        if (!kill_i) begin
          rsp_valid_o   = 1'b1;
          load_data_o   = load_data_q;
          exception_o   = exception_q;

          if (cmd_q == MEM_STORE) begin
            trace_wstrb_o = store_wstrb_q;
            trace_wdata_o = store_wdata_q;
          end
        end
      end

      default: ;
    endcase
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
            load_data_q     <= 32'b0;
            exception_q     <= '0;

            if ((cmd_i == MEM_STORE) && !input_misaligned) begin
              store_wstrb_q <= input_store_wstrb;
              store_wdata_q <= input_store_wdata;
            end else begin
              store_wstrb_q <= 4'b0000;
              store_wdata_q <= 32'b0;
            end

            if (!input_is_memory) begin
              // A benign local completion prevents an integration mistake
              // from deadlocking the pipeline. Architectural instructions
              // only request the LSU for MEM_LOAD or MEM_STORE.
              state_q <= LSU_RESP;
            end else if (input_misaligned) begin
              exception_q <= make_misaligned_exception(cmd_i, addr_i);
              state_q     <= LSU_RESP;
            end else begin
              state_q <= LSU_REQ;
            end
          end
        end

        LSU_REQ: begin
          if (kill_i) begin
            discard_q <= 1'b1;
          end

          if (dmem_m.req_ready) begin
            if (dmem_m.rsp_valid) begin
              if (kill_i || discard_q || rsp_ready_i) begin
                state_q <= LSU_IDLE;
              end else begin
                load_data_q <= response_load_data;
                exception_q <= response_exception;
                state_q     <= LSU_RESP;
              end
            end else if (kill_i || discard_q) begin
              state_q <= LSU_DROP;
            end else begin
              state_q <= LSU_WAIT;
            end
          end
        end

        LSU_WAIT: begin
          if (kill_i) begin
            if (dmem_m.rsp_valid) begin
              state_q <= LSU_IDLE;
            end else begin
              state_q <= LSU_DROP;
            end
          end else if (dmem_m.rsp_valid) begin
            if (rsp_ready_i) begin
              state_q <= LSU_IDLE;
            end else begin
              load_data_q <= response_load_data;
              exception_q <= response_exception;
              state_q     <= LSU_RESP;
            end
          end
        end

        LSU_DROP: begin
          if (dmem_m.rsp_valid) begin
            state_q <= LSU_IDLE;
          end
        end

        LSU_RESP: begin
          if (kill_i || rsp_ready_i) begin
            state_q <= LSU_IDLE;
          end
        end

        default: begin
          state_q <= LSU_IDLE;
        end
      endcase
    end
  end

endmodule
