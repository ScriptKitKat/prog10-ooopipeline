`include "tinker.sv"

module test_lq_backpressure;
    reg clk, rst;
    reg dispatch_en;
    reg [63:0] dispatch_base_val;
    reg [6:0] dispatch_base_tag;
    reg dispatch_base_ready;
    reg [63:0] dispatch_imm;
    reg [6:0] dispatch_dest_tag;
    reg [4:0] dispatch_rob_idx;
    reg [2:0] dispatch_epoch;
    reg [4:0] dispatch_opcode;
    reg cdb0_valid, cdb1_valid;
    reg [6:0] cdb0_tag, cdb1_tag;
    reg [63:0] cdb0_value, cdb1_value;
    wire mem_read_en;
    wire [63:0] mem_read_addr;
    reg [63:0] mem_read_data;
    reg sq_fwd_valid;
    reg [63:0] sq_fwd_data;
    wire cdb_valid;
    wire [6:0] cdb_tag;
    wire [63:0] cdb_value;
    wire [4:0] cdb_rob_idx;
    wire [2:0] cdb_epoch;
    wire br_resolved, br_taken;
    wire [63:0] br_target;
    wire [4:0] br_rob_idx_out;
    wire [2:0] br_epoch_out;
    reg cdb_stall;
    wire full;
    reg flush, br_squash;
    reg [4:0] br_squash_rob_idx, recover_tail;

    reg [63:0] observed_addr;

    load_queue dut(
        .clk(clk),
        .rst(rst),
        .dispatch_en(dispatch_en),
        .dispatch_base_val(dispatch_base_val),
        .dispatch_base_tag(dispatch_base_tag),
        .dispatch_base_ready(dispatch_base_ready),
        .dispatch_imm(dispatch_imm),
        .dispatch_dest_tag(dispatch_dest_tag),
        .dispatch_rob_idx(dispatch_rob_idx),
        .dispatch_epoch(dispatch_epoch),
        .dispatch_opcode(dispatch_opcode),
        .cdb0_valid(cdb0_valid),
        .cdb0_tag(cdb0_tag),
        .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid),
        .cdb1_tag(cdb1_tag),
        .cdb1_value(cdb1_value),
        .mem_read_en(mem_read_en),
        .mem_read_addr(mem_read_addr),
        .mem_read_data(mem_read_data),
        .sq_fwd_valid(sq_fwd_valid),
        .sq_fwd_data(sq_fwd_data),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .cdb_rob_idx(cdb_rob_idx),
        .cdb_epoch(cdb_epoch),
        .br_resolved(br_resolved),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_rob_idx_out(br_rob_idx_out),
        .br_epoch_out(br_epoch_out),
        .cdb_stall(cdb_stall),
        .full(full),
        .flush(flush),
        .br_squash(br_squash),
        .br_squash_rob_idx(br_squash_rob_idx),
        .recover_tail(recover_tail)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        dispatch_en = 0;
        dispatch_base_val = 64'd0;
        dispatch_base_tag = 7'd0;
        dispatch_base_ready = 1'b1;
        dispatch_imm = 64'd0;
        dispatch_dest_tag = 7'd0;
        dispatch_rob_idx = 5'd0;
        dispatch_epoch = 3'd0;
        dispatch_opcode = 5'h10; // LOAD
        cdb0_valid = 0; cdb1_valid = 0;
        cdb0_tag = 0; cdb1_tag = 0;
        cdb0_value = 0; cdb1_value = 0;
        mem_read_data = 64'hdeadbeef;
        sq_fwd_valid = 0;
        sq_fwd_data = 0;
        cdb_stall = 0;
        flush = 0;
        br_squash = 0;
        br_squash_rob_idx = 0;
        recover_tail = 0;
        observed_addr = 0;

        @(posedge clk);
        rst = 0;

        // Hold CDB stalled before any load can retire.
        cdb_stall = 1;

        // Dispatch load #1 @ 0x1000
        dispatch_en = 1;
        dispatch_base_val = 64'h1000;
        dispatch_dest_tag = 7'd10;
        dispatch_rob_idx = 5'd1;
        @(posedge clk);

        // Dispatch load #2 @ 0x2000
        dispatch_base_val = 64'h2000;
        dispatch_dest_tag = 7'd11;
        dispatch_rob_idx = 5'd2;
        @(posedge clk);
        #1 observed_addr = mem_read_addr;
        dispatch_en = 0;

        if (observed_addr != 64'h2000) begin
            $display("FAIL HOL blocking: mem_read_addr=%h expected=0x2000", observed_addr);
            $finish(1);
        end

        $display("PASS LQ progresses under CDB backpressure");
        $finish;
    end
endmodule
