`include "tinker.sv"

module test_alu_branch_squash;
    reg clk, rst;
    reg issue_valid;
    reg [4:0] issue_opcode;
    reg [63:0] issue_src1, issue_src2, issue_imm, issue_pc;
    reg [6:0] issue_dest_tag;
    reg [4:0] issue_rob_idx;
    wire issue_ready;

    wire cdb_valid;
    wire [6:0] cdb_tag;
    wire [63:0] cdb_value;
    wire [4:0] cdb_rob_idx;
    wire br_resolved;
    wire br_taken;
    wire [63:0] br_target;
    wire [4:0] br_rob_idx_out;

    reg cdb_stall;
    reg flush;
    reg br_squash;
    reg [4:0] br_squash_rob_idx;
    reg [4:0] recover_tail;

    alu_pipe dut(
        .clk(clk),
        .rst(rst),
        .issue_valid(issue_valid),
        .issue_opcode(issue_opcode),
        .issue_src1(issue_src1),
        .issue_src2(issue_src2),
        .issue_dest_tag(issue_dest_tag),
        .issue_rob_idx(issue_rob_idx),
        .issue_imm(issue_imm),
        .issue_pc(issue_pc),
        .issue_ready(issue_ready),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .cdb_rob_idx(cdb_rob_idx),
        .br_resolved(br_resolved),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_rob_idx_out(br_rob_idx_out),
        .cdb_stall(cdb_stall),
        .flush(flush),
        .br_squash(br_squash),
        .br_squash_rob_idx(br_squash_rob_idx),
        .recover_tail(recover_tail)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        issue_valid = 0;
        issue_opcode = 5'h19;   // ADDI
        issue_src1 = 64'd10;
        issue_src2 = 64'd0;
        issue_dest_tag = 7'd40;
        issue_rob_idx = 5'd5;
        issue_imm = 64'd1;
        issue_pc = 64'd0;
        cdb_stall = 0;
        flush = 0;
        br_squash = 0;
        br_squash_rob_idx = 5'd0;
        recover_tail = 5'd0;

        #2 rst = 0;

        issue_valid = 1;
        @(posedge clk);
        issue_valid = 0;

        // The issued op is younger than ROB idx 3 inside the active ring (3, 6).
        br_squash = 1;
        br_squash_rob_idx = 5'd3;
        recover_tail = 5'd6;
        @(posedge clk);
        br_squash = 0;

        if (cdb_valid !== 1'b0 || br_resolved !== 1'b0) begin
            $display("FAIL alu_branch_squash wrong_path_survived cdb_valid=%b br_resolved=%b cdb_rob_idx=%0d",
                     cdb_valid, br_resolved, cdb_rob_idx);
            $finish;
        end

        @(posedge clk);
        if (cdb_valid !== 1'b0) begin
            $display("FAIL alu_branch_squash wrong_path_reappeared cdb_valid=%b cdb_rob_idx=%0d",
                     cdb_valid, cdb_rob_idx);
        end else begin
            $display("PASS alu_branch_squash");
        end

        $finish;
    end
endmodule
