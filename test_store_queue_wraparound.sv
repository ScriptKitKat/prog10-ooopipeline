`include "tinker.sv"

module test_store_queue_wraparound;
    reg clk, rst;

    reg dispatch_en;
    reg [63:0] dispatch_addr_base_val;
    reg [6:0] dispatch_addr_base_tag;
    reg dispatch_addr_base_ready;
    reg [63:0] dispatch_data_val;
    reg [6:0] dispatch_data_tag;
    reg dispatch_data_ready;
    reg [63:0] dispatch_imm;
    reg [4:0] dispatch_rob_idx;
    reg [4:0] dispatch_opcode;

    reg cdb0_valid;
    reg [6:0] cdb0_tag;
    reg [63:0] cdb0_value;
    reg cdb1_valid;
    reg [6:0] cdb1_tag;
    reg [63:0] cdb1_value;

    reg commit_en1;
    reg [4:0] commit_rob_idx1;
    reg commit_en2;
    reg [4:0] commit_rob_idx2;
    wire mem_write_en;
    wire [63:0] mem_write_addr;
    wire [63:0] mem_write_data;

    reg fwd_check_en;
    reg [63:0] fwd_check_addr;
    reg [4:0] fwd_check_rob_idx;
    reg [4:0] rob_head_idx;

    reg load_exec_valid;
    reg [63:0] load_exec_addr;
    reg [4:0] load_exec_rob_idx;
    reg [4:0] load_exec_pc_idx;

    wire dep_has_unresolved_store;
    wire violation_valid;
    wire [4:0] violation_pc_idx;
    wire fwd_hit;
    wire [63:0] fwd_data;

    wire rob_store_addr_ready;
    wire rob_store_data_ready;
    wire [4:0] rob_store_addr_ready_idx;
    wire [4:0] rob_store_data_ready_idx;
    wire [63:0] rob_store_addr_value;
    wire [63:0] rob_store_ready_value;
    wire full;

    reg flush;
    reg br_squash;
    reg [4:0] br_squash_rob_idx;
    reg [4:0] recover_tail;

    store_queue dut(
        .clk(clk),
        .rst(rst),
        .dispatch_en(dispatch_en),
        .dispatch_addr_base_val(dispatch_addr_base_val),
        .dispatch_addr_base_tag(dispatch_addr_base_tag),
        .dispatch_addr_base_ready(dispatch_addr_base_ready),
        .dispatch_data_val(dispatch_data_val),
        .dispatch_data_tag(dispatch_data_tag),
        .dispatch_data_ready(dispatch_data_ready),
        .dispatch_imm(dispatch_imm),
        .dispatch_rob_idx(dispatch_rob_idx),
        .dispatch_opcode(dispatch_opcode),
        .cdb0_valid(cdb0_valid),
        .cdb0_tag(cdb0_tag),
        .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid),
        .cdb1_tag(cdb1_tag),
        .cdb1_value(cdb1_value),
        .commit_en1(commit_en1),
        .commit_rob_idx1(commit_rob_idx1),
        .commit_en2(commit_en2),
        .commit_rob_idx2(commit_rob_idx2),
        .mem_write_en(mem_write_en),
        .mem_write_addr(mem_write_addr),
        .mem_write_data(mem_write_data),
        .fwd_check_en(fwd_check_en),
        .fwd_check_addr(fwd_check_addr),
        .fwd_check_rob_idx(fwd_check_rob_idx),
        .rob_head_idx(rob_head_idx),
        .load_exec_valid(load_exec_valid),
        .load_exec_addr(load_exec_addr),
        .load_exec_rob_idx(load_exec_rob_idx),
        .load_exec_pc_idx(load_exec_pc_idx),
        .dep_has_unresolved_store(dep_has_unresolved_store),
        .violation_valid(violation_valid),
        .violation_pc_idx(violation_pc_idx),
        .fwd_hit(fwd_hit),
        .fwd_data(fwd_data),
        .rob_store_addr_ready(rob_store_addr_ready),
        .rob_store_data_ready(rob_store_data_ready),
        .rob_store_addr_ready_idx(rob_store_addr_ready_idx),
        .rob_store_data_ready_idx(rob_store_data_ready_idx),
        .rob_store_addr_value(rob_store_addr_value),
        .rob_store_ready_value(rob_store_ready_value),
        .full(full),
        .flush(flush),
        .br_squash(br_squash),
        .br_squash_rob_idx(br_squash_rob_idx),
        .recover_tail(recover_tail)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            dispatch_en = 1'b0;
            dispatch_addr_base_val = 64'd0;
            dispatch_addr_base_tag = 7'd0;
            dispatch_addr_base_ready = 1'b0;
            dispatch_data_val = 64'd0;
            dispatch_data_tag = 7'd0;
            dispatch_data_ready = 1'b0;
            dispatch_imm = 64'd0;
            dispatch_rob_idx = 5'd0;
            dispatch_opcode = 5'h13;
            cdb0_valid = 1'b0;
            cdb0_tag = 7'd0;
            cdb0_value = 64'd0;
            cdb1_valid = 1'b0;
            cdb1_tag = 7'd0;
            cdb1_value = 64'd0;
            commit_en1 = 1'b0;
            commit_rob_idx1 = 5'd0;
            commit_en2 = 1'b0;
            commit_rob_idx2 = 5'd0;
            fwd_check_en = 1'b0;
            fwd_check_addr = 64'd0;
            fwd_check_rob_idx = 5'd0;
            load_exec_valid = 1'b0;
            load_exec_addr = 64'd0;
            load_exec_rob_idx = 5'd0;
            load_exec_pc_idx = 5'd0;
            flush = 1'b0;
            br_squash = 1'b0;
            br_squash_rob_idx = 5'd0;
            recover_tail = 5'd0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        rob_head_idx = 5'd30; // ring head near wrap point
        clear_inputs();

        #12;
        rst = 1'b0;

        // Record a previously executed younger load at ROB idx 2.
        load_exec_valid = 1'b1;
        load_exec_addr = 64'h1000;
        load_exec_rob_idx = 5'd2;
        load_exec_pc_idx = 5'd17;
        @(posedge clk);
        #1;
        load_exec_valid = 1'b0;

        // Dispatch an older store at ROB idx 31 with unresolved data.
        dispatch_en = 1'b1;
        dispatch_addr_base_val = 64'h1000;
        dispatch_addr_base_ready = 1'b1;
        dispatch_data_tag = 7'd9;
        dispatch_data_ready = 1'b0;
        dispatch_imm = 64'd0;
        dispatch_rob_idx = 5'd31;
        dispatch_opcode = 5'h13;
        @(posedge clk);
        #1;
        dispatch_en = 1'b0;

        if (!dep_has_unresolved_store) begin
            $display("FAIL unresolved-store tracking should be set");
            $finish(1);
        end

        // Resolve that older store's data; this should produce a violation
        // against the recorded younger load across the ROB wrap boundary.
        cdb0_valid = 1'b1;
        cdb0_tag = 7'd9;
        cdb0_value = 64'hAAAA;
        @(posedge clk);
        #1;
        cdb0_valid = 1'b0;

        if (!violation_valid || violation_pc_idx !== 5'd17) begin
            $display("FAIL wrap violation learning: valid=%b pc_idx=%0d", violation_valid, violation_pc_idx);
            $finish(1);
        end

        // Dispatch another older store at ROB idx 1 (younger than idx 31, still older than load idx 2).
        dispatch_en = 1'b1;
        dispatch_addr_base_val = 64'h1000;
        dispatch_addr_base_ready = 1'b1;
        dispatch_data_val = 64'hBBBB;
        dispatch_data_ready = 1'b1;
        dispatch_imm = 64'd0;
        dispatch_rob_idx = 5'd1;
        dispatch_opcode = 5'h13;
        @(posedge clk);
        #1;
        dispatch_en = 1'b0;

        // Forwarding should pick ROB idx 1 store, not ROB idx 31 store.
        fwd_check_en = 1'b1;
        fwd_check_addr = 64'h1000;
        fwd_check_rob_idx = 5'd2;
        #1;

        if (!fwd_hit || fwd_data !== 64'hBBBB) begin
            $display("FAIL wrap forwarding: hit=%b data=0x%h", fwd_hit, fwd_data);
            $finish(1);
        end

        $display("PASS wraparound dependency + forwarding behavior");
        $finish;
    end
endmodule
