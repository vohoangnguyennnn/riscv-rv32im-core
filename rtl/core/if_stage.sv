// Instruction fetch optimized for the always-ready, one-cycle TCM.
// A single outstanding request and one output holding register are sufficient;
// the small stale tag drains a request invalidated by flush or redirect.
module if_stage #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
  input  logic           clk_i,
  input  logic           rst_i,
  input  logic           enable_i,
  input  logic           consume_i,
  input  logic           flush_i,
  input  logic           redirect_valid_i,
  input  logic [31:0]    redirect_pc_i,

  rv32_mem_if.master     imem_m,

  output logic           fetch_valid_o,
  output logic [31:0]    fetch_pc_o,
  output logic [31:0]    fetch_insn_o,
  output rv32_pkg::exc_t fetch_exc_o
);

  import rv32_pkg::*;

  typedef enum logic {
    IF_IDLE,
    IF_BUSY
  } if_state_e;

  if_state_e state_q;
  if_state_e state_d;

  word_t next_pc_q;
  word_t next_pc_d;
  word_t request_pc_q;
  word_t request_pc_d;
  logic  request_sent_q;
  logic  request_sent_d;
  logic  discard_q;
  logic  discard_d;
  logic  redirect_pending_q;
  logic  redirect_pending_d;

  logic  packet_valid_q;
  logic  packet_valid_d;
  word_t packet_pc_q;
  word_t packet_pc_d;
  word_t packet_insn_q;
  word_t packet_insn_d;
  exc_t  packet_exc_q;
  exc_t  packet_exc_d;

  logic  kill_event;
  logic  want_fetch;
  logic  launch_request;
  word_t launch_pc;
  logic  held_request;
  logic  request_fire;
  logic  request_stale;

  logic  response_seen;
  logic  response_stale;
  logic  response_live;
  word_t response_pc;
  word_t response_insn;
  exc_t  response_exc;
  logic  packet_consumed;
  logic  response_consumed;

  always_comb begin
    state_d            = state_q;
    next_pc_d          = next_pc_q;
    request_pc_d       = request_pc_q;
    request_sent_d     = request_sent_q;
    discard_d          = discard_q;
    redirect_pending_d = redirect_pending_q;

    packet_valid_d     = packet_valid_q;
    packet_pc_d        = packet_pc_q;
    packet_insn_d      = packet_insn_q;
    packet_exc_d       = packet_exc_q;

    kill_event         = flush_i || redirect_valid_i;
    want_fetch         = redirect_valid_i || (!flush_i && (enable_i || redirect_pending_q));
    launch_request     = 1'b0;
    launch_pc          = redirect_valid_i ? redirect_pc_i : next_pc_q;
    held_request       = (state_q == IF_BUSY) && !request_sent_q;

    response_seen      = 1'b0;
    response_stale     = 1'b0;
    response_live      = 1'b0;
    response_pc        = request_pc_q;
    response_insn      = 32'b0;
    response_exc       = '0;
    packet_consumed    = 1'b0;
    response_consumed  = 1'b0;

    fetch_valid_o      = 1'b0;
    fetch_pc_o         = 32'b0;
    fetch_insn_o       = 32'b0;
    fetch_exc_o        = '0;

    imem_m.req_valid   = 1'b0;
    imem_m.req_addr    = held_request ? request_pc_q : launch_pc;
    imem_m.req_write   = 1'b0;
    imem_m.req_wdata   = 32'b0;
    imem_m.req_wstrb   = 4'b0000;

    // IDLE starts a fetch when the output slot is free. A completed stale or
    // immediately consumed response can recycle the request slot in one cycle.
    if (!rst_i && want_fetch) begin
      if (state_q == IF_IDLE) begin
        launch_request = kill_event || !packet_valid_q || consume_i;
      end else if (request_sent_q && imem_m.rsp_valid) begin
        launch_request = redirect_valid_i || (!flush_i && !packet_valid_q && (discard_q || consume_i));
      end
    end

    if (!rst_i) begin
      if (held_request) begin
        imem_m.req_valid = 1'b1;
        imem_m.req_addr  = request_pc_q;
      end else if (launch_request) begin
        imem_m.req_valid = 1'b1;
        imem_m.req_addr  = launch_pc;
      end
    end

    request_fire  = imem_m.req_valid && imem_m.req_ready;
    request_stale = discard_q || kill_event;

    if (state_q == IF_BUSY) begin
      response_seen  = imem_m.rsp_valid && (request_sent_q || request_fire);
      response_pc    = request_pc_q;
      response_stale = request_stale;
    end else begin
      response_seen  = launch_request && request_fire && imem_m.rsp_valid;
      response_pc    = launch_pc;
      response_stale = 1'b0;
    end

    response_live = response_seen && !response_stale;
    if (response_live) begin
      if (imem_m.rsp_err) begin
        response_exc.valid = 1'b1;
        response_exc.cause = EXC_INST_ACCESS_FAULT;
        response_exc.tval  = response_pc;
      end else begin
        response_insn = imem_m.rsp_rdata;
      end
    end

    // A held packet has priority. A response falls through when possible and
    // is captured only when the pipeline does not consume it immediately.
    if (!rst_i && !kill_event) begin
      if (packet_valid_q) begin
        fetch_valid_o = 1'b1;
        fetch_pc_o    = packet_pc_q;
        fetch_insn_o  = packet_insn_q;
        fetch_exc_o   = packet_exc_q;
      end else if (response_live) begin
        fetch_valid_o = 1'b1;
        fetch_pc_o    = response_pc;
        fetch_insn_o  = response_insn;
        fetch_exc_o   = response_exc;
      end
    end

    packet_consumed   = packet_valid_q && !kill_event && consume_i;
    response_consumed = response_live && !packet_valid_q && !kill_event && consume_i;

    if (kill_event || packet_consumed) begin
      packet_valid_d = 1'b0;
    end

    if (response_live && !response_consumed) begin
      packet_valid_d = 1'b1;
      packet_pc_d    = response_pc;
      packet_insn_d  = response_insn;
      packet_exc_d   = response_exc;
    end

    // The newest redirect target is the next useful PC. A pure flush cancels
    // any remembered redirect while an older request drains.
    if (redirect_valid_i) begin
      next_pc_d          = redirect_pc_i;
      redirect_pending_d = 1'b1;
    end else if (flush_i) begin
      redirect_pending_d = 1'b0;
    end

    unique case (state_q)
      IF_IDLE: begin
        discard_d      = 1'b0;
        request_sent_d = 1'b0;

        if (launch_request) begin
          request_pc_d = launch_pc;

          if (request_fire) begin
            next_pc_d          = launch_pc + 32'd4;
            redirect_pending_d = 1'b0;

            if (!imem_m.rsp_valid) begin
              state_d        = IF_BUSY;
              request_sent_d = 1'b1;
            end
          end else begin
            state_d        = IF_BUSY;
            request_sent_d = 1'b0;
          end
        end
      end

      IF_BUSY: begin
        if (kill_event) begin
          discard_d = 1'b1;
        end

        if (!request_sent_q && request_fire) begin
          if (!request_stale) begin
            next_pc_d          = request_pc_q + 32'd4;
            redirect_pending_d = 1'b0;
          end

          if (imem_m.rsp_valid) begin
            state_d        = IF_IDLE;
            request_sent_d = 1'b0;
            discard_d      = 1'b0;
          end else begin
            request_sent_d = 1'b1;
            discard_d      = request_stale;
          end
        end else if (request_sent_q && imem_m.rsp_valid) begin
          state_d        = IF_IDLE;
          request_sent_d = 1'b0;
          discard_d      = 1'b0;

          if (launch_request) begin
            request_pc_d = launch_pc;
            state_d      = IF_BUSY;

            if (request_fire) begin
              request_sent_d     = 1'b1;
              next_pc_d          = launch_pc + 32'd4;
              redirect_pending_d = 1'b0;
            end else begin
              request_sent_d = 1'b0;
            end
          end
        end
      end

      default: begin
        state_d            = IF_IDLE;
        request_sent_d     = 1'b0;
        discard_d          = 1'b0;
        redirect_pending_d = 1'b0;
        packet_valid_d     = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q            <= IF_IDLE;
      next_pc_q          <= RESET_VECTOR;
      request_pc_q       <= RESET_VECTOR;
      request_sent_q     <= 1'b0;
      discard_q          <= 1'b0;
      redirect_pending_q <= 1'b0;
      packet_valid_q     <= 1'b0;
      packet_pc_q        <= 32'b0;
      packet_insn_q      <= 32'b0;
      packet_exc_q       <= '0;

      // A request accepted before reset cannot be cancelled. Drain its single
      // response before restarting from RESET_VECTOR.
      if ((state_q == IF_BUSY) && request_sent_q && !imem_m.rsp_valid) begin
        state_q        <= IF_BUSY;
        request_sent_q <= 1'b1;
        discard_q      <= 1'b1;
      end
    end else begin
      state_q            <= state_d;
      next_pc_q          <= next_pc_d;
      request_pc_q       <= request_pc_d;
      request_sent_q     <= request_sent_d;
      discard_q          <= discard_d;
      redirect_pending_q <= redirect_pending_d;
      packet_valid_q     <= packet_valid_d;
      packet_pc_q        <= packet_pc_d;
      packet_insn_q      <= packet_insn_d;
      packet_exc_q       <= packet_exc_d;
    end
  end

endmodule
