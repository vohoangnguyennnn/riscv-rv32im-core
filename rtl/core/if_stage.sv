// Blocking instruction-fetch front end with a one-entry fall-through buffer.
//
// At most one instruction-memory request is accepted without a matching
// response.  A request that encounters backpressure remains stable until it is
// accepted.  Responses bypass the buffer when the downstream pipeline consumes
// them immediately; otherwise they are held until consumed or flushed.
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

  typedef enum logic [1:0] {
    IF_IDLE,
    IF_REQ,
    IF_WAIT
  } if_state_e;

  if_state_e state_q;
  if_state_e state_d;

  // Address of the next architecturally useful fetch.  A redirect overwrites
  // this value, while an accepted non-stale request advances it by four.
  word_t fetch_pc_q;
  word_t fetch_pc_d;

  // PC and stale tag for the request held in IF_REQ or outstanding in IF_WAIT.
  word_t request_pc_q;
  word_t request_pc_d;
  logic  discard_q;
  logic  discard_d;

  // A redirect can arrive while an older request must still be drained.  Keep
  // the redirect pending so the target is issued as soon as the port is free,
  // even though redirect_valid_i itself is only a one-cycle event.
  logic redirect_pending_q;
  logic redirect_pending_d;

  // One-entry response skid buffer.  Normal TCM responses fall through to the
  // outputs; this storage is used only when the downstream stage cannot accept.
  logic  packet_valid_q;
  logic  packet_valid_d;
  word_t packet_pc_q;
  word_t packet_pc_d;
  word_t packet_insn_q;
  word_t packet_insn_d;
  exc_t  packet_exc_q;
  exc_t  packet_exc_d;

  logic  kill_event;
  logic  launch_request;
  word_t launch_pc;
  logic  request_fire;
  logic  request_stale;

  logic  response_seen;
  logic  response_stale;
  logic  response_live;
  word_t response_pc;
  word_t response_insn;
  exc_t  response_exc;
  logic  response_consumed;
  logic  packet_consumed;

  always_comb begin
    state_d            = state_q;
    fetch_pc_d         = fetch_pc_q;
    request_pc_d       = request_pc_q;
    discard_d          = discard_q;
    redirect_pending_d = redirect_pending_q;

    packet_valid_d     = packet_valid_q;
    packet_pc_d        = packet_pc_q;
    packet_insn_d      = packet_insn_q;
    packet_exc_d       = packet_exc_q;

    kill_event         = flush_i || redirect_valid_i;
    launch_request     = 1'b0;
    launch_pc          = fetch_pc_q;
    request_fire       = 1'b0;
    request_stale      = discard_q || kill_event;

    response_seen      = 1'b0;
    response_stale     = 1'b0;
    response_live      = 1'b0;
    response_pc        = request_pc_q;
    response_insn      = 32'b0;
    response_exc       = '0;
    response_consumed  = 1'b0;
    packet_consumed    = 1'b0;

    fetch_valid_o      = 1'b0;
    fetch_pc_o         = 32'b0;
    fetch_insn_o       = 32'b0;
    fetch_exc_o        = '0;

    imem_m.req_valid   = 1'b0;
    imem_m.req_addr    = fetch_pc_q;
    imem_m.req_write   = 1'b0;
    imem_m.req_wdata   = 32'b0;
    imem_m.req_wstrb   = 4'b0000;

    // Decide whether a free request slot may be recycled this cycle.  A live
    // response must either be consumed immediately or have buffer space; a
    // stale response consumes no front-end storage.
    if (!rst_i) begin
      unique case (state_q)
        IF_IDLE: begin
          if (redirect_valid_i) begin
            launch_request = 1'b1;
            launch_pc      = redirect_pc_i;
          end else if (!flush_i && (enable_i || redirect_pending_q) && (!packet_valid_q || consume_i)) begin
            launch_request = 1'b1;
            launch_pc      = fetch_pc_q;
          end
        end

        IF_WAIT: begin
          if (imem_m.rsp_valid) begin
            if (redirect_valid_i) begin
              launch_request = 1'b1;
              launch_pc      = redirect_pc_i;
            end else if (!flush_i && (enable_i || redirect_pending_q) && !packet_valid_q && (discard_q || consume_i)
            ) begin
              launch_request = 1'b1;
              launch_pc      = fetch_pc_q;
            end
          end
        end

        default: ;
      endcase
    end

    // IF_REQ owns the request channel until ready.  In IDLE, or while an old
    // response retires in IF_WAIT, launch_request may use the channel directly.
    if (!rst_i) begin
      if (state_q == IF_REQ) begin
        imem_m.req_valid = 1'b1;
        imem_m.req_addr  = request_pc_q;
      end else if (launch_request) begin
        imem_m.req_valid = 1'b1;
        imem_m.req_addr  = launch_pc;
      end
    end

    request_fire = imem_m.req_valid && imem_m.req_ready;

    // Associate every response with the PC captured for its request.  IF_IDLE
    // and IF_REQ also support a zero-latency test slave; the project TCM uses a
    // registered one-cycle response.
    unique case (state_q)
      IF_IDLE: begin
        response_seen  = request_fire && imem_m.rsp_valid;
        response_pc    = launch_pc;
        response_stale = 1'b0;
      end

      IF_REQ: begin
        response_seen  = request_fire && imem_m.rsp_valid;
        response_pc    = request_pc_q;
        response_stale = request_stale;
      end

      IF_WAIT: begin
        response_seen  = imem_m.rsp_valid;
        response_pc    = request_pc_q;
        response_stale = request_stale;
      end

      default: ;
    endcase

    response_live = response_seen && !response_stale;
    if (response_live) begin
      if (imem_m.rsp_err) begin
        response_insn      = 32'b0;
        response_exc.valid = 1'b1;
        response_exc.cause = EXC_INST_ACCESS_FAULT;
        response_exc.tval  = response_pc;
      end else begin
        response_insn = imem_m.rsp_rdata;
      end
    end

    // The buffered packet has priority over a fall-through response.  Redirect
    // and flush suppress all pre-existing packets in the cycle they occur.
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

    packet_consumed = packet_valid_q && !kill_event && consume_i;
    response_consumed = response_live && !packet_valid_q && !kill_event && consume_i;

    // A kill first invalidates the old buffered packet.  A fresh zero-latency
    // redirect response may then occupy the newly freed entry.
    if (kill_event || packet_consumed) begin
      packet_valid_d = 1'b0;
    end

    if (response_live && !response_consumed) begin
      packet_valid_d = 1'b1;
      packet_pc_d    = response_pc;
      packet_insn_d  = response_insn;
      packet_exc_d   = response_exc;
    end

    // Redirect is locally higher priority than flush.  A pure flush cancels a
    // remembered redirect; the system controller will provide the eventual
    // trap redirect after the precise-exception drain.
    if (redirect_valid_i) begin
      fetch_pc_d         = redirect_pc_i;
      redirect_pending_d = 1'b1;
    end else if (flush_i) begin
      redirect_pending_d = 1'b0;
    end

    unique case (state_q)
      IF_IDLE: begin
        discard_d = 1'b0;

        if (launch_request) begin
          request_pc_d = launch_pc;
          discard_d    = 1'b0;

          if (request_fire) begin
            fetch_pc_d         = launch_pc + 32'd4;
            redirect_pending_d = 1'b0;

            if (imem_m.rsp_valid) begin
              state_d = IF_IDLE;
            end else begin
              state_d = IF_WAIT;
            end
          end else begin
            state_d = IF_REQ;
          end
        end
      end

      IF_REQ: begin
        if (kill_event) begin
          discard_d = 1'b1;
        end

        if (request_fire) begin
          if (!request_stale) begin
            fetch_pc_d         = request_pc_q + 32'd4;
            redirect_pending_d = 1'b0;
          end

          if (imem_m.rsp_valid) begin
            state_d   = IF_IDLE;
            discard_d = 1'b0;
          end else begin
            state_d   = IF_WAIT;
            discard_d = request_stale;
          end
        end
      end

      IF_WAIT: begin
        if (kill_event) begin
          discard_d = 1'b1;
        end

        if (imem_m.rsp_valid) begin
          discard_d = 1'b0;

          if (launch_request) begin
            request_pc_d = launch_pc;

            if (request_fire) begin
              state_d            = IF_WAIT;
              fetch_pc_d         = launch_pc + 32'd4;
              redirect_pending_d = 1'b0;
            end else begin
              state_d = IF_REQ;
            end
          end else begin
            state_d = IF_IDLE;
          end
        end
      end

      default: begin
        state_d            = IF_IDLE;
        discard_d          = 1'b0;
        redirect_pending_d = 1'b0;
        packet_valid_d     = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q            <= IF_IDLE;
      fetch_pc_q         <= RESET_VECTOR;
      request_pc_q       <= RESET_VECTOR;
      discard_q          <= 1'b0;
      redirect_pending_q <= 1'b0;

      packet_valid_q     <= 1'b0;
      packet_pc_q        <= 32'b0;
      packet_insn_q      <= 32'b0;
      packet_exc_q       <= '0;

      // The memory interface has no request cancellation.  Preserve only the
      // fact that a pre-reset accepted request still needs to be drained; its
      // eventual response remains stale, and fetching restarts at RESET_VECTOR.
      if ((state_q == IF_WAIT) && !imem_m.rsp_valid) begin
        state_q   <= IF_WAIT;
        discard_q <= 1'b1;
      end
    end else begin
      state_q            <= state_d;
      fetch_pc_q         <= fetch_pc_d;
      request_pc_q       <= request_pc_d;
      discard_q          <= discard_d;
      redirect_pending_q <= redirect_pending_d;

      packet_valid_q     <= packet_valid_d;
      packet_pc_q        <= packet_pc_d;
      packet_insn_q      <= packet_insn_d;
      packet_exc_q       <= packet_exc_d;
    end
  end

endmodule
